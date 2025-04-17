# Módulo de Backup para WindowsBootRepairMCP
# Requiere privilegios de administrador

function Start-BackupModule {
    param (
        [hashtable]$Config
    )
    
    Write-Log "Iniciando módulo de Backup" -Module "Backup"
    
    # Verificar espacio disponible
    $systemDrive = $env:SystemDrive
    $freeSpace = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$systemDrive'").FreeSpace
    $requiredSpace = 10GB # Espacio mínimo requerido para backup
    
    if ($freeSpace -lt $requiredSpace) {
        Write-Log "Espacio insuficiente para crear backup. Se requieren al menos 10GB" -Level "ERROR" -Module "Backup"
        return $false
    }
    
    return $true
}

function Start-SystemBackup {
    param (
        [string]$BackupPath = (Join-Path $env:SystemDrive "WindowsBootRepairMCP_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')")
    )
    
    try {
        Write-Log "Iniciando backup del sistema" -Module "Backup"
        
        # Crear directorio de backup
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        Write-Log "Directorio de backup creado: $BackupPath" -Module "Backup"
        
        # Backup de archivos críticos del sistema
        $criticalFiles = @(
            "$env:SystemRoot\System32\config\SYSTEM",
            "$env:SystemRoot\System32\config\SOFTWARE",
            "$env:SystemRoot\System32\config\SAM",
            "$env:SystemRoot\System32\config\SECURITY",
            "$env:SystemRoot\System32\config\DEFAULT"
        )
        
        foreach ($file in $criticalFiles) {
            if (Test-Path $file) {
                $destFile = Join-Path $BackupPath (Split-Path $file -Leaf)
                Copy-Item -Path $file -Destination $destFile -Force
                Write-Log "Backup creado: $file -> $destFile" -Module "Backup"
            }
            else {
                Write-Log "Archivo no encontrado para backup: $file" -Level "WARNING" -Module "Backup"
            }
        }
        
        # Backup de configuración EFI
        $efiPath = "$env:SystemDrive\EFI"
        if (Test-Path $efiPath) {
            $efiBackupPath = Join-Path $BackupPath "EFI"
            Copy-Item -Path $efiPath -Destination $efiBackupPath -Recurse -Force
            Write-Log "Backup de EFI creado: $efiBackupPath" -Module "Backup"
        }
        
        # Exportar configuración BCD
        $bcdExportPath = Join-Path $BackupPath "bcd_export.txt"
        bcdedit /export $bcdExportPath
        Write-Log "Exportación BCD guardada: $bcdExportPath" -Module "Backup"
        
        # Backup de registro de arranque
        $bootFiles = @(
            "$env:SystemRoot\bootstat.dat",
            "$env:SystemRoot\boot.ini"
        )
        
        foreach ($file in $bootFiles) {
            if (Test-Path $file) {
                $destFile = Join-Path $BackupPath (Split-Path $file -Leaf)
                Copy-Item -Path $file -Destination $destFile -Force
                Write-Log "Backup de archivo de arranque creado: $file -> $destFile" -Module "Backup"
            }
        }
        
        # Crear archivo de metadatos del backup
        $metadata = @{
            "FechaBackup" = Get-Date
            "VersionWindows" = (Get-WmiObject Win32_OperatingSystem).Caption
            "ArchivosBackup" = $criticalFiles + $bootFiles
            "RutaBackup" = $BackupPath
        }
        
        $metadata | ConvertTo-Json | Out-File (Join-Path $BackupPath "backup_metadata.json")
        
        Write-Log "Backup completado exitosamente" -Module "Backup"
        return @{
            "Success" = $true
            "BackupPath" = $BackupPath
            "Metadata" = $metadata
        }
    }
    catch {
        Write-Log "Error al crear backup: $_" -Level "ERROR" -Module "Backup"
        return @{
            "Success" = $false
            "Error" = $_.Exception.Message
        }
    }
}

function Restore-SystemBackup {
    param (
        [string]$BackupPath
    )
    
    try {
        Write-Log "Iniciando restauración desde backup: $BackupPath" -Module "Backup"
        
        if (-not (Test-Path $BackupPath)) {
            Write-Log "Ruta de backup no encontrada: $BackupPath" -Level "ERROR" -Module "Backup"
            return $false
        }
        
        # Verificar archivo de metadatos
        $metadataPath = Join-Path $BackupPath "backup_metadata.json"
        if (-not (Test-Path $metadataPath)) {
            Write-Log "Archivo de metadatos no encontrado" -Level "ERROR" -Module "Backup"
            return $false
        }
        
        # Restaurar archivos críticos
        $criticalFiles = @(
            "$env:SystemRoot\System32\config\SYSTEM",
            "$env:SystemRoot\System32\config\SOFTWARE",
            "$env:SystemRoot\System32\config\SAM",
            "$env:SystemRoot\System32\config\SECURITY",
            "$env:SystemRoot\System32\config\DEFAULT"
        )
        
        foreach ($file in $criticalFiles) {
            $backupFile = Join-Path $BackupPath (Split-Path $file -Leaf)
            if (Test-Path $backupFile) {
                Copy-Item -Path $backupFile -Destination $file -Force
                Write-Log "Archivo restaurado: $backupFile -> $file" -Module "Backup"
            }
        }
        
        # Restaurar configuración EFI
        $efiBackupPath = Join-Path $BackupPath "EFI"
        if (Test-Path $efiBackupPath) {
            $efiPath = "$env:SystemDrive\EFI"
            Copy-Item -Path $efiBackupPath -Destination $efiPath -Recurse -Force
            Write-Log "Configuración EFI restaurada" -Module "Backup"
        }
        
        # Restaurar configuración BCD
        $bcdExportPath = Join-Path $BackupPath "bcd_export.txt"
        if (Test-Path $bcdExportPath) {
            bcdedit /import $bcdExportPath
            Write-Log "Configuración BCD restaurada" -Module "Backup"
        }
        
        # Restaurar archivos de arranque
        $bootFiles = @(
            "$env:SystemRoot\bootstat.dat",
            "$env:SystemRoot\boot.ini"
        )
        
        foreach ($file in $bootFiles) {
            $backupFile = Join-Path $BackupPath (Split-Path $file -Leaf)
            if (Test-Path $backupFile) {
                Copy-Item -Path $backupFile -Destination $file -Force
                Write-Log "Archivo de arranque restaurado: $backupFile -> $file" -Module "Backup"
            }
        }
        
        Write-Log "Restauración completada exitosamente" -Module "Backup"
        return $true
    }
    catch {
        Write-Log "Error al restaurar backup: $_" -Level "ERROR" -Module "Backup"
        return $false
    }
}

# Exportar funciones
Export-ModuleMember -Function Start-BackupModule, Start-SystemBackup, Restore-SystemBackup 