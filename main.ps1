#Requires -RunAsAdministrator

# Importar módulos
$configPath = Join-Path $PSScriptRoot "mcp.config.json"
$config = Get-Content $configPath | ConvertFrom-Json

# Variable global para el estado de ejecución
$script:ExecutionState = @{
    "Success" = $true
    "Errors" = @()
    "Warnings" = @()
    "BackupCreated" = $false
    "BackupPath" = ""
    "CurrentModule" = ""
    "StartTime" = Get-Date
}

# Función para cargar módulos
function Import-Module {
    param (
        [string]$ModulePath
    )
    if (Test-Path $ModulePath) {
        . $ModulePath
        return $true
    }
    return $false
}

# Función para manejar errores
function Handle-Error {
    param (
        [string]$ModuleName,
        [string]$ErrorMessage,
        [bool]$Critical = $true
    )
    
    $script:ExecutionState.Errors += "[$ModuleName] $ErrorMessage"
    Write-Log "Error en módulo $ModuleName`: $ErrorMessage" -Level "ERROR"
    
    if ($Critical) {
        $script:ExecutionState.Success = $false
        
        # Si tenemos un backup y el error es crítico, intentar restaurar
        if ($script:ExecutionState.BackupCreated) {
            Write-Log "Intentando restaurar backup debido a error crítico" -Level "WARNING"
            try {
                & "Restore-SystemBackup" -BackupPath $script:ExecutionState.BackupPath
            }
            catch {
                Write-Log "Error al restaurar backup: $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }
}

# Inicializar logging
$loggingModule = $config.modules.logging.path
if (Import-Module $loggingModule) {
    Initialize-Logging -Config $config.logging
}
else {
    Write-Error "No se pudo cargar el módulo de logging. Abortando ejecución."
    exit 1
}

# Cargar y ejecutar módulos en orden de prioridad
$modules = $config.modules | Get-Member -MemberType NoteProperty | 
    Sort-Object { $config.modules.($_.Name).priority }

foreach ($module in $modules) {
    $moduleConfig = $config.modules.($module.Name)
    if ($moduleConfig.enabled) {
        $script:ExecutionState.CurrentModule = $module.Name
        Write-Log "Iniciando módulo: $($module.Name)" -Module $module.Name
        
        if (Import-Module $moduleConfig.path) {
            try {
                $result = & "Start-$($module.Name)Module" -Config $config
                
                # Verificar resultado del módulo
                if ($result -is [hashtable] -and $result.ContainsKey("Success")) {
                    if (-not $result.Success) {
                        $errorMessage = if ($result.ContainsKey("Error")) { $result.Error } else { "Error desconocido" }
                        Handle-Error -ModuleName $module.Name -ErrorMessage $errorMessage
                    }
                    
                    # Si es el módulo de backup, guardar el estado
                    if ($module.Name -eq "backup" -and $result.Success) {
                        $script:ExecutionState.BackupCreated = $true
                        $script:ExecutionState.BackupPath = $result.BackupPath
                    }
                }
            }
            catch {
                Handle-Error -ModuleName $module.Name -ErrorMessage $_.Exception.Message
            }
        }
        else {
            Handle-Error -ModuleName $module.Name -ErrorMessage "No se pudo cargar el módulo" -Critical $true
        }
    }
}

# Generar reporte final
$reportPath = Join-Path $config.logging.path "execution_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
@"
=== Reporte de Ejecución ===
Fecha: $(Get-Date)
Duración: $((Get-Date).Subtract($script:ExecutionState.StartTime).ToString())
Estado: $(if ($script:ExecutionState.Success) { "ÉXITO" } else { "FALLO" })

Módulos Ejecutados:
$(foreach ($module in $modules) { "- $($module.Name)" })

Errores:
$(foreach ($error in $script:ExecutionState.Errors) { "- $error" })

Advertencias:
$(foreach ($warning in $script:ExecutionState.Warnings) { "- $warning" })

$(if ($script:ExecutionState.BackupCreated) {
@"
Backup:
- Creado: Sí
- Ruta: $($script:ExecutionState.BackupPath)
"@
})
"@ | Out-File -FilePath $reportPath

# Finalizar proceso
if ($script:ExecutionState.Success) {
    Write-Log "Proceso de reparación completado exitosamente" -Level "INFO"
}
else {
    Write-Log "Proceso de reparación falló. Verificar reporte: $reportPath" -Level "ERROR"
    exit 1
} 