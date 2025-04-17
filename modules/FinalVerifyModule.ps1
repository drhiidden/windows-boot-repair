# Módulo de Verificación Final
function Start-FinalVerifyModule {
    param (
        [hashtable]$Config,
        [hashtable]$DiagnosisResults,
        [hashtable]$BootRepairResults,
        [int]$RetryCount = 0
    )
    
    Write-Log "Iniciando verificación final del sistema" -Module "FinalVerify"
    
    $results = @{
        "Success" = $true
        "Errors" = @()
        "Warnings" = @()
        "VerifySteps" = @()
        "RetryCount" = $RetryCount
    }
    
    $tempFiles = @()
    
    try {
        # Verificar resultados del diagnóstico
        if (-not $DiagnosisResults.Success) {
            $results.Errors += "El diagnóstico inicial falló: $($DiagnosisResults.Errors -join ', ')"
            $results.Success = $false
        }
        
        # Verificar resultados de la reparación
        if (-not $BootRepairResults.Success) {
            $results.Errors += "La reparación de arranque falló: $($BootRepairResults.Errors -join ', ')"
            $results.Success = $false
        }
        
        # Verificar espacio en disco
        $systemInfo = Get-SystemDrive
        if (-not $systemInfo) {
            $results.Errors += "No se pudo obtener información del sistema"
            $results.Success = $false
            return $results
        }
        
        $spaceCheck = Test-PartitionSpace -SystemInfo $systemInfo
        if (-not $spaceCheck.Success) {
            $results.Errors += $spaceCheck.Errors
            $results.Success = $false
        }
        $results.Warnings += $spaceCheck.Warnings
        
        # Verificar servicios críticos
        Write-Log "Verificando servicios críticos" -Module "FinalVerify"
        foreach ($service in $Config.system.required_services) {
            try {
                $serviceStatus = Get-Service $service -ErrorAction Stop
                if ($serviceStatus.Status -ne "Running") {
                    $results.Errors += "Servicio crítico $service no está en ejecución (Estado: $($serviceStatus.Status))"
                    $results.Success = $false
                }
            }
            catch {
                $results.Errors += "No se pudo verificar el servicio $service : $($_.Exception.Message)"
                $results.Success = $false
            }
        }
        
        # Verificar rutas críticas
        Write-Log "Verificando rutas críticas" -Module "FinalVerify"
        foreach ($path in $Config.system.critical_paths) {
            if (-not (Test-Path $path)) {
                $results.Errors += "Ruta crítica no encontrada: $path"
                $results.Success = $false
            }
        }
        
        # Verificar archivos de arranque
        Write-Log "Verificando archivos de arranque" -Module "FinalVerify"
        $bootFiles = @(
            "bootmgr",
            "boot.ini",
            "bootstat.dat",
            "BCD"
        )
        
        foreach ($file in $bootFiles) {
            $filePath = if ($systemInfo.BootType -eq "UEFI") {
                "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\$file"
            }
            else {
                "$($systemInfo.SystemDrive.DriveLetter)\$file"
            }
            
            if (-not (Test-Path $filePath)) {
                $results.Errors += "Archivo de arranque no encontrado: $file"
                $results.Success = $false
            }
        }
        
        # Verificar integridad del BCD
        Write-Log "Verificando integridad del BCD" -Module "FinalVerify"
        $bcdOutput = Join-Path $LogPath "bcd_verify.log"
        $tempFiles += $bcdOutput
        
        try {
            $bcdProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/v" -NoNewWindow -Wait -RedirectStandardOutput $bcdOutput -RedirectStandardError "$bcdOutput.err"
            $tempFiles += "$bcdOutput.err"
            
            if (Test-Path "$bcdOutput.err") {
                $bcdErrors = Get-Content -Path "$bcdOutput.err" -Encoding UTF8 -ErrorAction Stop
                if ($bcdErrors) {
                    $results.Errors += "Error al verificar BCD: $bcdErrors"
                    $results.Success = $false
                }
            }
        }
        catch {
            $results.Errors += "Error al verificar BCD: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Verificar disco del sistema
        Write-Log "Ejecutando verificación final de disco" -Module "FinalVerify"
        $chkdskOutput = Join-Path $LogPath "chkdsk_final.log"
        $tempFiles += $chkdskOutput
        
        try {
            $chkdskProcess = Start-Process -FilePath "chkdsk.exe" -ArgumentList "$($systemInfo.SystemDrive.DriveLetter) /f /r /x" -NoNewWindow -Wait -RedirectStandardOutput $chkdskOutput -RedirectStandardError "$chkdskOutput.err"
            $tempFiles += "$chkdskOutput.err"
            
            if (Test-Path "$chkdskOutput.err") {
                $chkdskErrors = Get-Content -Path "$chkdskOutput.err" -Encoding UTF8 -ErrorAction Stop
                if ($chkdskErrors) {
                    $results.Errors += "Error en verificación final de disco: $chkdskErrors"
                    $results.Success = $false
                }
            }
            
            $chkdskContent = Get-Content $chkdskOutput -Encoding UTF8 -ErrorAction Stop
            if ($chkdskContent -match "error|Error|ERROR|corrupt|Corrupt|CORRUPT") {
                $results.Errors += "Se encontraron errores en la verificación final de disco"
                $results.Success = $false
            }
        }
        catch {
            $results.Errors += "Error al ejecutar verificación final de disco: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Verificar integridad del sistema
        Write-Log "Ejecutando verificación final de archivos del sistema" -Module "FinalVerify"
        $sfcOutput = Join-Path $LogPath "sfc_final.log"
        $tempFiles += $sfcOutput
        
        try {
            $sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow /offbootdir=$($systemInfo.SystemDrive.DriveLetter) /offwindir=$($systemInfo.SystemDrive.DriveLetter)\Windows" -NoNewWindow -Wait -RedirectStandardOutput $sfcOutput -RedirectStandardError "$sfcOutput.err"
            $tempFiles += "$sfcOutput.err"
            
            if (Test-Path "$sfcOutput.err") {
                $sfcErrors = Get-Content -Path "$sfcOutput.err" -Encoding UTF8 -ErrorAction Stop
                if ($sfcErrors) {
                    $results.Errors += "Error en verificación final de archivos del sistema: $sfcErrors"
                    $results.Success = $false
                }
            }
            
            $sfcContent = Get-Content $sfcOutput -Encoding UTF8 -ErrorAction Stop
            if ($sfcContent -match "error|Error|ERROR|corrupt|Corrupt|CORRUPT|integrity|Integrity|INTEGRITY") {
                $results.Errors += "Se encontraron errores en la verificación final de archivos del sistema"
                $results.Success = $false
            }
        }
        catch {
            $results.Errors += "Error al ejecutar verificación final de archivos del sistema: $($_.Exception.Message)"
            $results.Success = $false
        }
        
        # Sistema de reintentos para errores no críticos
        if (-not $results.Success -and $RetryCount -lt 3) {
            $nonCriticalErrors = $results.Errors | Where-Object { $_ -notmatch "critical|Critical|CRITICAL" }
            if ($nonCriticalErrors) {
                Write-Log "Reintentando verificación final (Intento $($RetryCount + 1) de 3)" -Module "FinalVerify"
                Start-Sleep -Seconds 30
                $retryResults = Start-FinalVerifyModule -Config $Config -DiagnosisResults $DiagnosisResults -BootRepairResults $BootRepairResults -RetryCount ($RetryCount + 1)
                $results = $retryResults
            }
        }
        
        Write-Log "Verificación final completada" -Module "FinalVerify"
        return $results
    }
    catch {
        Write-Log "Error durante la verificación final: $($_.Exception.Message)" -Level "ERROR" -Module "FinalVerify"
        $results.Errors += "Error durante la verificación final: $($_.Exception.Message)"
        $results.Success = $false
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
                    Write-Log "Error al eliminar archivo temporal $file : $($_.Exception.Message)" -Level "WARNING" -Module "FinalVerify"
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
                    Write-Log "Error al eliminar log antiguo $($_.Name) : $($_.Exception.Message)" -Level "WARNING" -Module "FinalVerify"
                }
            }
        }
    }
}

# Exportar funciones
Export-ModuleMember -Function Start-FinalVerifyModule 