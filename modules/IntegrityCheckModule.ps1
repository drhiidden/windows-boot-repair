# Módulo de Verificación de Integridad para WindowsBootRepairMCP
# Requiere privilegios de administrador

$script:ModuleDependencies = @{
    "backup" = @("logging")
    "diagnosis" = @("backup", "logging")
    "bootrepair" = @("diagnosis", "backup", "logging")
    "finalverify" = @("bootrepair", "diagnosis", "backup", "logging")
}

$script:CriticalSystemPaths = @(
    "$env:SystemRoot\System32\config",
    "$env:SystemRoot\System32\drivers",
    "$env:SystemRoot\boot",
    "$env:SystemDrive\EFI"
)

function Start-IntegrityCheckModule {
    param (
        [hashtable]$Config
    )
    
    Write-Log "Iniciando verificación de integridad del sistema" -Module "IntegrityCheck"
    
    $results = @{
        "Success" = $true
        "Errors" = @()
        "Warnings" = @()
        "ModuleStatus" = @{}
    }
    
    # Verificar privilegios de administrador
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $results.Errors += "Se requieren privilegios de administrador para ejecutar este script"
        $results.Success = $false
        return $results
    }
    
    # Verificar rutas críticas del sistema
    foreach ($path in $script:CriticalSystemPaths) {
        if (-not (Test-Path $path)) {
            $results.Errors += "Ruta crítica no encontrada: $path"
            $results.Success = $false
        }
    }
    
    # Verificar espacio en disco
    $systemDrive = $env:SystemDrive
    $freeSpace = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$systemDrive'").FreeSpace
    $requiredSpace = 20GB # Espacio mínimo requerido para operaciones
    
    if ($freeSpace -lt $requiredSpace) {
        $results.Errors += "Espacio insuficiente en disco. Se requieren al menos 20GB"
        $results.Success = $false
    }
    
    # Verificar módulos y sus dependencias
    foreach ($moduleName in $Config.modules.PSObject.Properties.Name) {
        $moduleConfig = $Config.modules.$moduleName
        
        if ($moduleConfig.enabled) {
            # Verificar existencia del archivo del módulo
            if (-not (Test-Path $moduleConfig.path)) {
                $results.Errors += "Módulo no encontrado: $moduleName ($($moduleConfig.path))"
                $results.Success = $false
                continue
            }
            
            # Verificar dependencias
            if ($script:ModuleDependencies.ContainsKey($moduleName)) {
                foreach ($dependency in $script:ModuleDependencies[$moduleName]) {
                    if (-not $Config.modules.$dependency.enabled) {
                        $results.Errors += "Módulo $moduleName requiere $dependency habilitado"
                        $results.Success = $false
                    }
                }
            }
            
            # Verificar permisos de archivo
            try {
                $acl = Get-Acl $moduleConfig.path
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $hasAccess = $acl.Access | Where-Object { $_.IdentityReference.Value -eq $currentUser -and $_.FileSystemRights -match "Read|Execute" }
                
                if (-not $hasAccess) {
                    $results.Errors += "Sin permisos de lectura/ejecución en módulo: $moduleName"
                    $results.Success = $false
                }
            }
            catch {
                $errorMessage = $_.Exception.Message
                $results.Errors += "Error al verificar permisos de $moduleName`: $errorMessage"
                $results.Success = $false
            }
        }
    }
    
    # Verificar entorno de ejecución
    $osInfo = Get-WmiObject Win32_OperatingSystem
    if (-not $osInfo.Caption -match "Windows") {
        $results.Warnings += "Este script está diseñado para Windows. Se detectó: $($osInfo.Caption)"
    }
    
    # Verificar estado de servicios críticos
    $criticalServices = @("RemoteRegistry", "Winmgmt")
    foreach ($service in $criticalServices) {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne "Running") {
            $results.Warnings += "Servicio crítico no está en ejecución: $service"
        }
    }
    
    # Verificar conectividad de red (para futuras actualizaciones)
    try {
        $testConnection = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -WarningAction SilentlyContinue
        if (-not $testConnection.TcpTestSucceeded) {
            $results.Warnings += "Sin conectividad de red. Algunas funciones pueden no estar disponibles"
        }
    }
    catch {
        $results.Warnings += "No se pudo verificar la conectividad de red"
    }
    
    # Registrar resultados
    if ($results.Success) {
        Write-Log "Verificación de integridad completada exitosamente" -Module "IntegrityCheck"
    }
    else {
        Write-Log "Verificación de integridad falló: $($results.Errors -join '; ')" -Level "ERROR" -Module "IntegrityCheck"
    }
    
    foreach ($warning in $results.Warnings) {
        Write-Log "Advertencia: $warning" -Level "WARNING" -Module "IntegrityCheck"
    }
    
    return $results
}

# Exportar funciones
Export-ModuleMember -Function Start-IntegrityCheckModule 