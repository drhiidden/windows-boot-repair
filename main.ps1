#Requires -RunAsAdministrator

# Importar módulos
$configPath = Join-Path $PSScriptRoot "mcp.config.json"
$config = Get-Content $configPath | ConvertFrom-Json

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

# Inicializar logging
$loggingModule = $config.modules.logging.path
if (Import-Module $loggingModule) {
    Initialize-Logging -Config $config.logging
}

# Cargar y ejecutar módulos en orden de prioridad
$modules = $config.modules | Get-Member -MemberType NoteProperty | 
    Sort-Object { $config.modules.($_.Name).priority }

foreach ($module in $modules) {
    $moduleConfig = $config.modules.($module.Name)
    if ($moduleConfig.enabled) {
        Write-Log "Iniciando módulo: $($module.Name)"
        if (Import-Module $moduleConfig.path) {
            try {
                & "Start-$($module.Name)Module"
            }
            catch {
                Write-Log "Error en módulo $($module.Name): $_" -Level "ERROR"
            }
        }
    }
}

# Finalizar proceso
Write-Log "Proceso de reparación completado" 