# Módulo de Reparación de Arranque
function Start-BootRepairModule {
    param (
        [hashtable]$Config,
        [hashtable]$DiagnosisResults
    )
    
    Write-Log "Iniciando reparación del gestor de arranque" -Module "BootRepair"
    
    $results = @{
        "Success" = $true
        "Errors" = @()
        "Warnings" = @()
        "RepairSteps" = @()
        "BackupRestored" = $false
    }
    
    $tempFiles = @()
    $criticalFiles = @()
    
    try {
        # Verificar si podemos proceder basado en el diagnóstico
        if (-not $DiagnosisResults.CanProceed) {
            $results.Errors += "No se puede proceder con la reparación debido a problemas críticos detectados en el diagnóstico"
            $results.Success = $false
            return $results
        }
        
        # Obtener información del sistema
        $systemInfo = Get-SystemDrive
        if (-not $systemInfo) {
            $results.Errors += "No se pudo obtener información del sistema"
            $results.Success = $false
            return $results
        }
        
        # Obtener configuración de arranque
        $bootConfig = Get-BootConfiguration -SystemInfo $systemInfo
        if (-not $bootConfig) {
            $results.Errors += "No se pudo obtener configuración de arranque"
            $results.Success = $false
            return $results
        }
    
        $bootrepairLog = Join-Path $Config.logging.path "bootrepair.log"
        $criticalFiles += $bootrepairLog
        
        # Crear backup antes de proceder
        Write-Log "Creando backup de la configuración de arranque" -Module "BootRepair"
        $backupPath = Join-Path $Config.backup.path "boot_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        
        # Verificar espacio necesario para backup
        $requiredSpace = 0
        if ($systemInfo.BootType -eq "UEFI") {
            $requiredSpace = (Get-ChildItem "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\*" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        else {
            $requiredSpace = (Get-ChildItem "$($systemInfo.SystemDrive.DriveLetter)\boot*" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        
        # Agregar espacio para BCD y logs
        $requiredSpace += 100MB
        
        # Verificar espacio disponible
        $backupDrive = Split-Path $backupPath -Qualifier
        $freeSpace = (Get-PSDrive $backupDrive[0]).Free
        if ($freeSpace -lt $requiredSpace) {
            $results.Errors += "Espacio insuficiente para backup. Requerido: $([math]::Round($requiredSpace/1GB, 2))GB, Disponible: $([math]::Round($freeSpace/1GB, 2))GB"
            $results.Success = $false
            return $results
        }
        
        # Backup de BCD con manejo de errores
        try {
            $bcdBackupFile = Join-Path $backupPath "bcd_backup.txt"
            $criticalFiles += $bcdBackupFile
            $bcdProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/export `"$bcdBackupFile`"" -NoNewWindow -Wait -RedirectStandardOutput "$bcdBackupFile.out" -RedirectStandardError "$bcdBackupFile.err"
            $criticalFiles += @("$bcdBackupFile.out", "$bcdBackupFile.err")
            
            if (Test-Path "$bcdBackupFile.err") {
                $bcdErrors = Get-Content -Path "$bcdBackupFile.err" -Encoding UTF8 -ErrorAction Stop
                if ($bcdErrors) {
                    throw "Error al exportar BCD: $bcdErrors"
                }
            }
            
            if (-not (Test-Path $bcdBackupFile)) {
                throw "No se pudo crear el backup del BCD"
            }
            
            $results.RepairSteps += "Backup de BCD creado en $backupPath"
        }
        catch {
            Write-Log "Error al crear backup de BCD: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
            $results.Errors += "Error al crear backup de BCD: $($_.Exception.Message)"
            $results.Success = $false
            return $results
        }
        
        # Preparar script de diskpart según el tipo de arranque
        if ($systemInfo.BootType -eq "UEFI") {
            Write-Log "Configurando reparación para arranque UEFI" -Module "BootRepair"
            
            # Backup de archivos EFI
            try {
                $efiBackupPath = Join-Path $backupPath "EFI"
                New-Item -ItemType Directory -Path $efiBackupPath -Force | Out-Null
                Copy-Item "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\*" $efiBackupPath -Recurse -Force
                $results.RepairSteps += "Backup de archivos EFI creado"
            }
            catch {
                Write-Log "Error al crear backup de archivos EFI: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al crear backup de archivos EFI: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
    
    # Asignar letra a la partición EFI
    $diskpartScript = @"
list disk
select disk 0
list partition
select partition 1
assign letter=M
exit
"@
    
            $diskpartOutput = Join-Path $backupPath "diskpart.log"
            $criticalFiles += $diskpartOutput
            
            try {
                $diskpartProcess = Start-Process -FilePath "diskpart.exe" -ArgumentList "/s `"$diskpartScript`"" -NoNewWindow -Wait -RedirectStandardOutput $diskpartOutput -RedirectStandardError "$diskpartOutput.err"
                $criticalFiles += "$diskpartOutput.err"
                
                if (Test-Path "$diskpartOutput.err") {
                    $diskpartErrors = Get-Content -Path "$diskpartOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($diskpartErrors) {
                        throw "Error en diskpart: $diskpartErrors"
                    }
                }
                
                $results.RepairSteps += "Asignada letra M: a partición EFI"
            }
            catch {
                Write-Log "Error al asignar letra a partición EFI: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al asignar letra a partición EFI: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
            
            # Reparar archivos de arranque UEFI
            Write-Log "Reparando archivos de arranque UEFI" -Module "BootRepair"
            try {
                $bcdbootOutput = Join-Path $backupPath "bcdboot.log"
                $criticalFiles += $bcdbootOutput
                
                $bcdbootProcess = Start-Process -FilePath "bcdboot.exe" -ArgumentList "$($systemInfo.SystemDrive.DriveLetter)\Windows /s M: /f UEFI" -NoNewWindow -Wait -RedirectStandardOutput $bcdbootOutput -RedirectStandardError "$bcdbootOutput.err"
                $criticalFiles += "$bcdbootOutput.err"
                
                if (Test-Path "$bcdbootOutput.err") {
                    $bcdbootErrors = Get-Content -Path "$bcdbootOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bcdbootErrors) {
                        throw "Error al reparar archivos UEFI: $bcdbootErrors"
                    }
                }
                
                $results.RepairSteps += "Reparados archivos de arranque UEFI"
            }
            catch {
                Write-Log "Error al reparar archivos UEFI: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al reparar archivos UEFI: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
            
            # Reconstruir BCD
            Write-Log "Reconstruyendo BCD en modo UEFI" -Module "BootRepair"
            try {
                $bcdeditOutput = Join-Path $backupPath "bcdedit.log"
                $criticalFiles += $bcdeditOutput
                
                $bcdeditProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set {bootmgr} path \EFI\Microsoft\Boot\bootmgfw.efi" -NoNewWindow -Wait -RedirectStandardOutput $bcdeditOutput -RedirectStandardError "$bcdeditOutput.err"
                $criticalFiles += "$bcdeditOutput.err"
                
                if (Test-Path "$bcdeditOutput.err") {
                    $bcdeditErrors = Get-Content -Path "$bcdeditOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bcdeditErrors) {
                        throw "Error al reconstruir BCD: $bcdeditErrors"
                    }
                }
                
                $results.RepairSteps += "Reconstruido BCD en modo UEFI"
            }
            catch {
                Write-Log "Error al reconstruir BCD: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al reconstruir BCD: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
        }
        else {
            Write-Log "Configurando reparación para arranque BIOS" -Module "BootRepair"
            
            # Backup de archivos de arranque
            try {
                Copy-Item "$($systemInfo.SystemDrive.DriveLetter)\boot*" $backupPath -Force
                $results.RepairSteps += "Backup de archivos de arranque creado"
            }
            catch {
                Write-Log "Error al crear backup de archivos de arranque: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al crear backup de archivos de arranque: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
            
            # Reparar MBR y sector de arranque
            Write-Log "Reparando MBR y sector de arranque" -Module "BootRepair"
            try {
                $bootrecOutput = Join-Path $backupPath "bootrec.log"
                $criticalFiles += $bootrecOutput
                
                # Reparar MBR
                $bootrecProcess = Start-Process -FilePath "bootrec.exe" -ArgumentList "/fixmbr" -NoNewWindow -Wait -RedirectStandardOutput $bootrecOutput -RedirectStandardError "$bootrecOutput.err"
                $criticalFiles += "$bootrecOutput.err"
                
                if (Test-Path "$bootrecOutput.err") {
                    $bootrecErrors = Get-Content -Path "$bootrecOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bootrecErrors) {
                        throw "Error al reparar MBR: $bootrecErrors"
                    }
                }
    
    # Reparar sector de arranque
                $bootrecProcess = Start-Process -FilePath "bootrec.exe" -ArgumentList "/fixboot" -NoNewWindow -Wait -RedirectStandardOutput $bootrecOutput -RedirectStandardError "$bootrecOutput.err"
                
                if (Test-Path "$bootrecOutput.err") {
                    $bootrecErrors = Get-Content -Path "$bootrecOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bootrecErrors) {
                        throw "Error al reparar sector de arranque: $bootrecErrors"
                    }
                }
                
                $results.RepairSteps += "Reparados MBR y sector de arranque"
            }
            catch {
                Write-Log "Error al reparar MBR/sector de arranque: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al reparar MBR/sector de arranque: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
            
            # Reconstruir BCD
            Write-Log "Reconstruyendo BCD en modo BIOS" -Module "BootRepair"
            try {
                $bootrecOutput = Join-Path $backupPath "bootrec_scan.log"
                $criticalFiles += $bootrecOutput
                
                # Escanear sistemas operativos
                $bootrecProcess = Start-Process -FilePath "bootrec.exe" -ArgumentList "/scanos" -NoNewWindow -Wait -RedirectStandardOutput $bootrecOutput -RedirectStandardError "$bootrecOutput.err"
                $criticalFiles += "$bootrecOutput.err"
                
                if (Test-Path "$bootrecOutput.err") {
                    $bootrecErrors = Get-Content -Path "$bootrecOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bootrecErrors) {
                        throw "Error al escanear sistemas operativos: $bootrecErrors"
                    }
                }
    
    # Reconstruir BCD
                $bootrecProcess = Start-Process -FilePath "bootrec.exe" -ArgumentList "/rebuildbcd" -NoNewWindow -Wait -RedirectStandardOutput $bootrecOutput -RedirectStandardError "$bootrecOutput.err"
                
                if (Test-Path "$bootrecOutput.err") {
                    $bootrecErrors = Get-Content -Path "$bootrecOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bootrecErrors) {
                        throw "Error al reconstruir BCD: $bootrecErrors"
                    }
                }
                
                $results.RepairSteps += "Reconstruido BCD en modo BIOS"
            }
            catch {
                Write-Log "Error al reconstruir BCD: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al reconstruir BCD: $($_.Exception.Message)"
                $results.Success = $false
                return $results
            }
        }
        
        # Verificar archivos de arranque
        $bootFiles = @(
            "bootmgr",
            "boot.ini",
            "bootstat.dat",
            "BCD"
        )
        
        $missingFiles = @()
        foreach ($file in $bootFiles) {
            $filePath = if ($systemInfo.BootType -eq "UEFI") {
                "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\$file"
            }
            else {
                "$($systemInfo.SystemDrive.DriveLetter)\$file"
            }
            
            if (-not (Test-Path $filePath)) {
                $missingFiles += $file
                $results.Errors += "Archivo de arranque no encontrado después de la reparación: $file"
                $results.Success = $false
            }
        }
        
        # Si hay archivos faltantes, restaurar backup
        if ($missingFiles.Count -gt 0) {
            Write-Log "Restaurando backup debido a archivos faltantes" -Module "BootRepair"
            
            try {
                if ($systemInfo.BootType -eq "UEFI") {
                    Copy-Item "$backupPath\EFI\*" "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\" -Recurse -Force
                }
                else {
                    Copy-Item "$backupPath\*" "$($systemInfo.SystemDrive.DriveLetter)\" -Force
                }
                
                $bcdImportOutput = Join-Path $backupPath "bcd_import.log"
                $criticalFiles += $bcdImportOutput
                
                $bcdeditProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/import `"$bcdBackupFile`"" -NoNewWindow -Wait -RedirectStandardOutput $bcdImportOutput -RedirectStandardError "$bcdImportOutput.err"
                $criticalFiles += "$bcdImportOutput.err"
                
                if (Test-Path "$bcdImportOutput.err") {
                    $bcdImportErrors = Get-Content -Path "$bcdImportOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bcdImportErrors) {
                        throw "Error al importar BCD: $bcdImportErrors"
                    }
                }
                
                $results.BackupRestored = $true
                $results.RepairSteps += "Backup restaurado debido a archivos faltantes"
            }
            catch {
                Write-Log "Error al restaurar backup: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al restaurar backup: $($_.Exception.Message)"
                $results.Success = $false
            }
        }
    
    # Verificar resultados
        $logContent = Get-Content $bootrepairLog -Encoding UTF8 -ErrorAction Stop
        if ($logContent -match "error|Error|ERROR|critical|Critical|CRITICAL") {
            $results.Errors += "Se encontraron errores durante la reparación"
            $results.Success = $false
            
            # Restaurar backup si hay errores críticos
            if ($logContent -match "critical|Critical|CRITICAL") {
                Write-Log "Restaurando backup debido a errores críticos" -Module "BootRepair"
                
                try {
                    if ($systemInfo.BootType -eq "UEFI") {
                        Copy-Item "$backupPath\EFI\*" "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\" -Recurse -Force
                    }
                    else {
                        Copy-Item "$backupPath\*" "$($systemInfo.SystemDrive.DriveLetter)\" -Force
                    }
                    
                    $bcdImportOutput = Join-Path $backupPath "bcd_import.log"
                    $criticalFiles += $bcdImportOutput
                    
                    $bcdeditProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/import `"$bcdBackupFile`"" -NoNewWindow -Wait -RedirectStandardOutput $bcdImportOutput -RedirectStandardError "$bcdImportOutput.err"
                    $criticalFiles += "$bcdImportOutput.err"
                    
                    if (Test-Path "$bcdImportOutput.err") {
                        $bcdImportErrors = Get-Content -Path "$bcdImportOutput.err" -Encoding UTF8 -ErrorAction Stop
                        if ($bcdImportErrors) {
                            throw "Error al importar BCD: $bcdImportErrors"
                        }
                    }
                    
                    $results.BackupRestored = $true
                    $results.RepairSteps += "Backup restaurado debido a errores críticos"
                }
                catch {
                    Write-Log "Error al restaurar backup: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                    $results.Errors += "Error al restaurar backup: $($_.Exception.Message)"
                    $results.Success = $false
                }
            }
    }
    
    Write-Log "Reparación de arranque completada" -Module "BootRepair"
        return $results
    }
    catch {
        Write-Log "Error durante la reparación de arranque: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
        $results.Errors += "Error durante la reparación: $($_.Exception.Message)"
        $results.Success = $false
        
        # Intentar restaurar backup en caso de error
        if (Test-Path $backupPath) {
            Write-Log "Restaurando backup debido a error durante la reparación" -Module "BootRepair"
            try {
                if ($systemInfo.BootType -eq "UEFI") {
                    Copy-Item "$backupPath\EFI\*" "$($systemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\" -Recurse -Force
                }
                else {
                    Copy-Item "$backupPath\*" "$($systemInfo.SystemDrive.DriveLetter)\" -Force
                }
                
                $bcdImportOutput = Join-Path $backupPath "bcd_import.log"
                $criticalFiles += $bcdImportOutput
                
                $bcdeditProcess = Start-Process -FilePath "bcdedit.exe" -ArgumentList "/import `"$bcdBackupFile`"" -NoNewWindow -Wait -RedirectStandardOutput $bcdImportOutput -RedirectStandardError "$bcdImportOutput.err"
                $criticalFiles += "$bcdImportOutput.err"
                
                if (Test-Path "$bcdImportOutput.err") {
                    $bcdImportErrors = Get-Content -Path "$bcdImportOutput.err" -Encoding UTF8 -ErrorAction Stop
                    if ($bcdImportErrors) {
                        throw "Error al importar BCD: $bcdImportErrors"
                    }
                }
                
                $results.BackupRestored = $true
                $results.RepairSteps += "Backup restaurado debido a error durante la reparación"
            }
            catch {
                Write-Log "Error al restaurar backup: $($_.Exception.Message)" -Level "ERROR" -Module "BootRepair"
                $results.Errors += "Error al restaurar backup: $($_.Exception.Message)"
            }
        }
        
        return $results
    }
    finally {
        # Limpiar solo archivos temporales, preservar archivos críticos
        foreach ($file in $tempFiles) {
            if (Test-Path $file -and $file -notin $criticalFiles) {
                try {
                    Remove-Item $file -Force
                }
                catch {
                    Write-Log "Error al eliminar archivo temporal $file : $($_.Exception.Message)" -Level "WARNING" -Module "BootRepair"
                }
            }
        }
        
        # Limpiar logs antiguos excepto los críticos
        $logRetentionDays = $Config.logging.retention_days
        $logPath = $Config.logging.path
        if (Test-Path $logPath) {
            Get-ChildItem -Path $logPath -File | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays) -and $_.FullName -notin $criticalFiles
            } | ForEach-Object {
                try {
                    Remove-Item $_.FullName -Force
                }
                catch {
                    Write-Log "Error al eliminar log antiguo $($_.Name) : $($_.Exception.Message)" -Level "WARNING" -Module "BootRepair"
                }
            }
        }
    }
}

# Exportar funciones
Export-ModuleMember -Function Start-BootRepairModule 