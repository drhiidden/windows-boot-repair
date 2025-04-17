# Módulo de Diagnóstico
function Start-DiagnosisModule {
    param (
        [hashtable]$Config
    )
    
    Write-Log "Iniciando diagnóstico del sistema" -Module "Diagnosis"
    
    $results = @{
        "Success" = $true
        "Errors" = @()
        "Warnings" = @()
        "SystemInfo" = $null
        "BootConfig" = $null
        "DiskHealth" = $null
        "SystemFiles" = $null
        "Severity" = "LOW"  # LOW, MEDIUM, HIGH, CRITICAL
        "CanProceed" = $true
    }
    
    $tempFiles = @()
    
    try {
        # Verificar permisos de administrador
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $results.Errors += "Se requieren privilegios de administrador para ejecutar el diagnóstico"
            $results.Success = $false
            $results.Severity = "CRITICAL"
            $results.CanProceed = $false
            return $results
        }
        
        # Verificar servicios críticos
        $criticalServices = $Config.system.required_services
        foreach ($service in $criticalServices) {
            try {
                $serviceStatus = Get-Service $service -ErrorAction Stop
                if ($serviceStatus.Status -ne "Running") {
                    $results.Warnings += "Servicio crítico $service no está en ejecución (Estado: $($serviceStatus.Status))"
                    $results.Success = $false
                    $results.Severity = "HIGH"
                }
            }
            catch {
                $results.Errors += "No se pudo verificar el servicio $service : $($_.Exception.Message)"
                $results.Success = $false
                $results.Severity = "HIGH"
            }
        }
        
        # Verificar rutas críticas
        foreach ($path in $Config.system.critical_paths) {
            if (-not (Test-Path $path)) {
                $results.Errors += "Ruta crítica no encontrada: $path"
                $results.Success = $false
                $results.Severity = "CRITICAL"
                $results.CanProceed = $false
            }
        }
        
        # Obtener información del sistema
        $results.SystemInfo = Get-SystemDrive
        if (-not $results.SystemInfo) {
            $results.Errors += "No se pudo obtener información del sistema"
            $results.Success = $false
            $results.Severity = "CRITICAL"
            $results.CanProceed = $false
            return $results
        }
        
        # Verificar espacio en particiones
        $spaceCheck = Test-PartitionSpace -SystemInfo $results.SystemInfo
        if (-not $spaceCheck.Success) {
            $results.Errors += $spaceCheck.Errors
            $results.Success = $false
            $results.Severity = "HIGH"
            $results.CanProceed = $false
        }
        $results.Warnings += $spaceCheck.Warnings
        
        # Verificar partición EFI para sistemas UEFI
        if ($results.SystemInfo.BootType -eq "UEFI" -and -not $results.SystemInfo.EFIPartition) {
            $results.Errors += "No se encontró la partición EFI en sistema UEFI"
            $results.Success = $false
            $results.Severity = "CRITICAL"
            $results.CanProceed = $false
        }
        
        # Obtener configuración de arranque
        $results.BootConfig = Get-BootConfiguration -SystemInfo $results.SystemInfo
        if (-not $results.BootConfig) {
            $results.Errors += "No se pudo obtener configuración de arranque"
            $results.Success = $false
            $results.Severity = "HIGH"
            $results.CanProceed = $false
        }
        
        # Verificar disco del sistema
        $systemDrive = $results.SystemInfo.SystemDrive.DriveLetter
        Write-Log "Ejecutando chkdsk en $systemDrive" -Module "Diagnosis"
        $chkdskOutput = Join-Path $LogPath "diagnosis_output.log"
        $tempFiles += $chkdskOutput
        
        # Ejecutar chkdsk con codificación UTF-8 y manejo de errores
        try {
            $chkdskProcess = Start-Process -FilePath "chkdsk.exe" -ArgumentList "$systemDrive /f /r /x" -NoNewWindow -Wait -RedirectStandardOutput $chkdskOutput -RedirectStandardError "$chkdskOutput.error"
            $chkdskContent = Get-Content -Path $chkdskOutput -Encoding UTF8 -ErrorAction Stop
            if (Test-Path "$chkdskOutput.error") {
                $chkdskErrors = Get-Content -Path "$chkdskOutput.error" -Encoding UTF8 -ErrorAction Stop
                $tempFiles += "$chkdskOutput.error"
                if ($chkdskErrors) {
                    Add-Content -Path $chkdskOutput -Value "`nErrores de chkdsk:`n$chkdskErrors"
                }
            }
        }
        catch {
            Write-Log "Error al ejecutar chkdsk: $($_.Exception.Message)" -Level "ERROR" -Module "Diagnosis"
            $results.Errors += "Error al ejecutar chkdsk: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Verificar estado SMART con manejo de codificación
        Write-Log "Verificando estado SMART de los discos" -Module "Diagnosis"
        try {
            $smartOutput = Join-Path $LogPath "smart_status.log"
            $tempFiles += $smartOutput
            $smartProcess = Start-Process -FilePath "wmic.exe" -ArgumentList "diskdrive get status" -NoNewWindow -Wait -RedirectStandardOutput $smartOutput -RedirectStandardError "$smartOutput.error"
            $smartStatus = Get-Content -Path $smartOutput -Encoding UTF8 -ErrorAction Stop
            if (Test-Path "$smartOutput.error") {
                $smartErrors = Get-Content -Path "$smartOutput.error" -Encoding UTF8 -ErrorAction Stop
                $tempFiles += "$smartOutput.error"
                if ($smartErrors) {
                    Add-Content -Path $smartOutput -Value "`nErrores SMART:`n$smartErrors"
                }
            }
            Add-Content -Path $chkdskOutput -Value "`nEstado SMART:`n$smartStatus"
        }
        catch {
            Write-Log "Error al verificar estado SMART: $($_.Exception.Message)" -Level "ERROR" -Module "Diagnosis"
            $results.Errors += "Error al verificar estado SMART: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Analizar resultados de chkdsk
        $chkdskContent = Get-Content $chkdskOutput -Encoding UTF8 -ErrorAction Stop
        $results.DiskHealth = @{
            "ChkdskErrors" = $chkdskContent -match "error|Error|ERROR|corrupt|Corrupt|CORRUPT"
            "SMARTStatus" = $smartStatus -match "Error|Pred Fail|Bad|BAD"
            "LogFile" = $chkdskOutput
        }
        
        if ($results.DiskHealth.ChkdskErrors) {
            $results.Errors += "Se encontraron errores en chkdsk"
            $results.Success = $false
            $results.Severity = "HIGH"
            $results.CanProceed = $false
        }
        
        if ($results.DiskHealth.SMARTStatus) {
            $results.Errors += "Se detectaron problemas en el estado SMART"
            $results.Success = $false
            $results.Severity = "CRITICAL"
            $results.CanProceed = $false
        }
        
        # Verificar integridad del sistema
        Write-Log "Ejecutando SFC" -Module "Diagnosis"
        $sfcOutput = Join-Path $LogPath "sfc_output.log"
        $tempFiles += $sfcOutput
        try {
            $sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow /offbootdir=$systemDrive /offwindir=$systemDrive\Windows" -NoNewWindow -Wait -RedirectStandardOutput $sfcOutput -RedirectStandardError "$sfcOutput.error"
            if (Test-Path "$sfcOutput.error") {
                $sfcErrors = Get-Content -Path "$sfcOutput.error" -Encoding UTF8 -ErrorAction Stop
                $tempFiles += "$sfcOutput.error"
                if ($sfcErrors) {
                    Add-Content -Path $sfcOutput -Value "`nErrores SFC:`n$sfcErrors"
                }
            }
        }
        catch {
            Write-Log "Error al ejecutar SFC: $($_.Exception.Message)" -Level "ERROR" -Module "Diagnosis"
            $results.Errors += "Error al ejecutar SFC: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Verificar imagen del sistema
        Write-Log "Ejecutando DISM" -Module "Diagnosis"
        $dismOutput = Join-Path $LogPath "dism_output.log"
        $tempFiles += $dismOutput
        try {
            $dismProcess = Start-Process -FilePath "DISM.exe" -ArgumentList "/Image:$systemDrive /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -RedirectStandardOutput $dismOutput -RedirectStandardError "$dismOutput.error"
            if (Test-Path "$dismOutput.error") {
                $dismErrors = Get-Content -Path "$dismOutput.error" -Encoding UTF8 -ErrorAction Stop
                $tempFiles += "$dismOutput.error"
                if ($dismErrors) {
                    Add-Content -Path $dismOutput -Value "`nErrores DISM:`n$dismErrors"
                }
            }
        }
        catch {
            Write-Log "Error al ejecutar DISM: $($_.Exception.Message)" -Level "ERROR" -Module "Diagnosis"
            $results.Errors += "Error al ejecutar DISM: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Analizar resultados de SFC y DISM
        $results.SystemFiles = @{
            "SFCErrors" = (Get-Content $sfcOutput -Encoding UTF8 -ErrorAction Stop) -match "error|Error|ERROR|corrupt|Corrupt|CORRUPT|integrity|Integrity|INTEGRITY"
            "DISMErrors" = (Get-Content $dismOutput -Encoding UTF8 -ErrorAction Stop) -match "error|Error|ERROR|corrupt|Corrupt|CORRUPT|integrity|Integrity|INTEGRITY"
            "SFCLog" = $sfcOutput
            "DISMLog" = $dismOutput
        }
        
        if ($results.SystemFiles.SFCErrors) {
            $results.Errors += "Se encontraron errores en la verificación de archivos del sistema (SFC)"
            $results.Success = $false
            $results.Severity = "MEDIUM"
        }
        
        if ($results.SystemFiles.DISMErrors) {
            $results.Errors += "Se encontraron errores en la imagen del sistema (DISM)"
            $results.Success = $false
            $results.Severity = "HIGH"
            $results.CanProceed = $false
        }
        
        # Verificar archivos de arranque
        foreach ($bootFile in $results.BootConfig.BootFiles) {
            if (-not $bootFile.Exists) {
                $results.Errors += "Archivo de arranque faltante: $($bootFile.Name)"
                $results.Success = $false
                $results.Severity = "HIGH"
                $results.CanProceed = $false
            }
        }
        
        Write-Log "Diagnóstico completado con severidad: $($results.Severity)" -Module "Diagnosis"
        return $results
    }
    catch {
        Write-Log "Error durante el diagnóstico: $($_.Exception.Message)" -Level "ERROR" -Module "Diagnosis"
        $results.Errors += "Error durante el diagnóstico: $($_.Exception.Message)"
        $results.Success = $false
        $results.Severity = "CRITICAL"
        $results.CanProceed = $false
        return $results
    }
    finally {
        # Limpiar archivos temporales
        foreach ($file in $tempFiles) {
            if (Test-Path $file) {
                try {
                    Remove-Item $file -Force
                }
                catch {
                    Write-Log "Error al eliminar archivo temporal $file : $($_.Exception.Message)" -Level "WARNING" -Module "Diagnosis"
                }
            }
        }
        
        # Limpiar logs antiguos
        $logRetentionDays = $Config.logging.retention_days
        $logPath = $Config.logging.path
        if (Test-Path $logPath) {
            Get-ChildItem -Path $logPath -File | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays)
            } | ForEach-Object {
                try {
                    Remove-Item $_.FullName -Force
                }
                catch {
                    Write-Log "Error al eliminar log antiguo $($_.Name) : $($_.Exception.Message)" -Level "WARNING" -Module "Diagnosis"
                }
            }
        }
    }
}

# Exportar funciones
Export-ModuleMember -Function Start-DiagnosisModule 