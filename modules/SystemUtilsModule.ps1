# Módulo de Utilidades del Sistema
# Requiere privilegios de administrador

function Get-SystemDrive {
    param (
        [switch]$IncludeEFI
    )
    
    $results = @{
        "SystemDrive" = $null
        "EFIPartition" = $null
        "BootType" = $null
        "Partitions" = @()
    }
    
    try {
        # Detectar tipo de arranque (BIOS/UEFI)
        $firmwareType = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty BIOSVersion
        $isUEFI = Test-Path "$env:SystemDrive\EFI"
        $results.BootType = if ($isUEFI) { "UEFI" } else { "BIOS" }
        
        # Obtener información de discos y particiones
        $disks = Get-WmiObject -Class Win32_DiskDrive
        foreach ($disk in $disks) {
            $partitions = $disk | Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} WHERE AssocClass = Win32_DiskDriveToDiskPartition"
            
            foreach ($partition in $partitions) {
                $logicalDisks = $partition | Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} WHERE AssocClass = Win32_LogicalDiskToPartition"
                
                foreach ($logicalDisk in $logicalDisks) {
                    $partitionInfo = @{
                        "DriveLetter" = $logicalDisk.DeviceID
                        "Size" = [math]::Round($logicalDisk.Size / 1GB, 2)
                        "FreeSpace" = [math]::Round($logicalDisk.FreeSpace / 1GB, 2)
                        "FileSystem" = $logicalDisk.FileSystem
                        "IsSystem" = $logicalDisk.DeviceID -eq $env:SystemDrive
                        "IsEFI" = $false
                    }
                    
                    # Verificar si es partición EFI
                    if ($isUEFI) {
                        $efiPath = "$($logicalDisk.DeviceID)\EFI"
                        if (Test-Path $efiPath) {
                            $partitionInfo.IsEFI = $true
                            $results.EFIPartition = $partitionInfo
                        }
                    }
                    
                    # Identificar unidad del sistema
                    if ($partitionInfo.IsSystem) {
                        $results.SystemDrive = $partitionInfo
                    }
                    
                    $results.Partitions += $partitionInfo
                }
            }
        }
        
        # Si no se encontró la unidad del sistema, usar la unidad actual
        if (-not $results.SystemDrive) {
            $currentDrive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
            $results.SystemDrive = @{
                "DriveLetter" = $currentDrive.DeviceID
                "Size" = [math]::Round($currentDrive.Size / 1GB, 2)
                "FreeSpace" = [math]::Round($currentDrive.FreeSpace / 1GB, 2)
                "FileSystem" = $currentDrive.FileSystem
                "IsSystem" = $true
                "IsEFI" = $false
            }
        }
        
        return $results
    }
    catch {
        Write-Log "Error al detectar unidades del sistema: $($_.Exception.Message)" -Level "ERROR" -Module "SystemUtils"
        return $null
    }
}

function Test-PartitionSpace {
    param (
        [hashtable]$SystemInfo,
        [double]$RequiredSpaceGB = 20
    )
    
    $results = @{
        "Success" = $true
        "Errors" = @()
        "Warnings" = @()
    }
    
    try {
        # Verificar espacio en unidad del sistema
        if ($SystemInfo.SystemDrive.FreeSpace -lt $RequiredSpaceGB) {
            $results.Errors += "Espacio insuficiente en unidad del sistema ($($SystemInfo.SystemDrive.DriveLetter)). Se requieren $RequiredSpaceGB GB, disponibles: $($SystemInfo.SystemDrive.FreeSpace) GB"
            $results.Success = $false
        }
        
        # Verificar espacio en partición EFI si existe
        if ($SystemInfo.EFIPartition) {
            $minEFISpace = 1 # 1 GB mínimo para EFI
            if ($SystemInfo.EFIPartition.FreeSpace -lt $minEFISpace) {
                $results.Errors += "Espacio insuficiente en partición EFI ($($SystemInfo.EFIPartition.DriveLetter)). Se requieren $minEFISpace GB, disponibles: $($SystemInfo.EFIPartition.FreeSpace) GB"
                $results.Success = $false
            }
        }
        
        # Verificar espacio en otras particiones
        foreach ($partition in $SystemInfo.Partitions) {
            if (-not $partition.IsSystem -and -not $partition.IsEFI) {
                if ($partition.FreeSpace -lt 5) { # 5 GB mínimo para otras particiones
                    $results.Warnings += "Espacio bajo en partición $($partition.DriveLetter): $($partition.FreeSpace) GB disponibles"
                }
            }
        }
        
        return $results
    }
    catch {
        Write-Log "Error al verificar espacio en particiones: $($_.Exception.Message)" -Level "ERROR" -Module "SystemUtils"
        return @{
            "Success" = $false
            "Errors" = @("Error al verificar espacio: $($_.Exception.Message)")
            "Warnings" = @()
        }
    }
}

function Get-BootConfiguration {
    param (
        [hashtable]$SystemInfo
    )
    
    $results = @{
        "BootType" = $SystemInfo.BootType
        "BCDLocation" = $null
        "BootFiles" = @()
        "Configuration" = @{}
    }
    
    try {
        # Obtener ubicación del BCD
        if ($SystemInfo.BootType -eq "UEFI") {
            $results.BCDLocation = "$($SystemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\BCD"
        }
        else {
            $results.BCDLocation = "$($SystemInfo.SystemDrive.DriveLetter)\Boot\BCD"
        }
        
        # Verificar archivos de arranque
        $bootFiles = @(
            "bootmgr",
            "boot.ini",
            "bootstat.dat",
            "BCD"
        )
        
        foreach ($file in $bootFiles) {
            $filePath = if ($SystemInfo.BootType -eq "UEFI") {
                "$($SystemInfo.EFIPartition.DriveLetter)\EFI\Microsoft\Boot\$file"
            }
            else {
                "$($SystemInfo.SystemDrive.DriveLetter)\$file"
            }
            
            $results.BootFiles += @{
                "Name" = $file
                "Path" = $filePath
                "Exists" = Test-Path $filePath
            }
        }
        
        # Obtener configuración actual del BCD
        if (Test-Path $results.BCDLocation) {
            $bcdOutput = bcdedit /export "$env:TEMP\bcd_export.txt"
            if (Test-Path "$env:TEMP\bcd_export.txt") {
                $results.Configuration = Get-Content "$env:TEMP\bcd_export.txt"
                Remove-Item "$env:TEMP\bcd_export.txt" -Force
            }
        }
        
        return $results
    }
    catch {
        Write-Log "Error al obtener configuración de arranque: $($_.Exception.Message)" -Level "ERROR" -Module "SystemUtils"
        return $null
    }
}

# Exportar funciones
Export-ModuleMember -Function Get-SystemDrive, Test-PartitionSpace, Get-BootConfiguration 