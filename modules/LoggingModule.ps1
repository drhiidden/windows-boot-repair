# Módulo de Logging
$script:LogPath = $null
$script:LogLevel = "INFO"
$script:LogRetention = "7d"
$script:WindowsLogPath = $null
$script:MediaLogPath = $null
$script:LogBuffer = @()

function Test-WindowsDrive {
    param (
        [string]$DriveLetter
    )
    
    # Verificar si existe la unidad
    if (-not (Test-Path "${DriveLetter}:")) {
        return $false
    }
    
    # Verificar si contiene la carpeta Windows
    $windowsPath = Join-Path "${DriveLetter}:" "Windows"
    if (-not (Test-Path $windowsPath)) {
        return $false
    }
    
    # Verificar si es una instalación de Windows válida
    $system32Path = Join-Path $windowsPath "System32"
    if (-not (Test-Path $system32Path)) {
        return $false
    }
    
    # Verificar si es NTFS
    $drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'"
    if ($drive.FileSystem -ne "NTFS") {
        return $false
    }
    
    return $true
}

function Find-WindowsDrive {
    # Obtener todas las unidades NTFS
    $ntfsDrives = Get-WmiObject -Class Win32_LogicalDisk | 
        Where-Object { $_.FileSystem -eq "NTFS" -and $_.DeviceID -ne "X:" }
    
    foreach ($drive in $ntfsDrives) {
        $driveLetter = $drive.DeviceID[0]
        if (Test-WindowsDrive -DriveLetter $driveLetter) {
            return $driveLetter
        }
    }
    
    return $null
}

function Test-EFIPartition {
    param (
        [string]$DriveLetter
    )
    
    # Verificar si existe la unidad
    if (-not (Test-Path "${DriveLetter}:")) {
        return $false
    }
    
    # Verificar si es FAT32 (típico para particiones EFI)
    $drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'"
    if ($drive.FileSystem -ne "FAT32") {
        return $false
    }
    
    # Verificar tamaño (aproximadamente 100MB)
    $sizeMB = [math]::Round($drive.Size / 1MB)
    if ($sizeMB -lt 90 -or $sizeMB -gt 110) {
        return $false
    }
    
    # Verificar si contiene la estructura EFI
    $efiPath = Join-Path "${DriveLetter}:" "EFI"
    if (-not (Test-Path $efiPath)) {
        return $false
    }
    
    # Verificar si contiene la carpeta Microsoft/Boot
    $bootPath = Join-Path $efiPath "Microsoft\Boot"
    if (-not (Test-Path $bootPath)) {
        return $false
    }
    
    return $true
}

function Find-EFIPartition {
    # Obtener todas las unidades FAT32
    $fat32Drives = Get-WmiObject -Class Win32_LogicalDisk | 
        Where-Object { $_.FileSystem -eq "FAT32" -and $_.DeviceID -ne "X:" }
    
    foreach ($drive in $fat32Drives) {
        $driveLetter = $drive.DeviceID[0]
        if (Test-EFIPartition -DriveLetter $driveLetter) {
            return $driveLetter
        }
    }
    
    return $null
}

function Initialize-Logging {
    param (
        [PSCustomObject]$Config
    )
    $script:LogLevel = $Config.level
    $script:LogRetention = $Config.retention

    # Detectar entorno
    $isWinPE = $env:SystemDrive -eq "X:"
    $script:IsWinPE = $isWinPE

    # Configurar rutas de logging
    if ($isWinPE) {
        # En WinPE, buscar la unidad de Windows
        $windowsDrive = Find-WindowsDrive
        if ($windowsDrive) {
            Write-Log "Unidad de Windows detectada: ${windowsDrive}:" -Module "System"
            $script:WindowsLogPath = Join-Path "${windowsDrive}:" "Windows\Logs\WindowsBootRepairMCP"
            $script:MediaLogPath = Join-Path $Config.path "logs"
        } else {
            Write-Log "No se pudo detectar la unidad de Windows" -Level "WARNING" -Module "System"
            $script:MediaLogPath = Join-Path $Config.path "logs"
            $script:WindowsLogPath = $null
        }
        
        # Buscar partición EFI
        $efiDrive = Find-EFIPartition
        if ($efiDrive) {
            Write-Log "Partición EFI detectada: ${efiDrive}:" -Module "System"
        } else {
            Write-Log "No se pudo detectar la partición EFI" -Level "WARNING" -Module "System"
        }
    } else {
        # En Windows normal
        $script:WindowsLogPath = Join-Path $env:SystemRoot "Logs\WindowsBootRepairMCP"
        $script:MediaLogPath = Join-Path $Config.path "logs"
    }

    # Crear directorios de logs si no existen
    if ($script:WindowsLogPath -and -not (Test-Path $script:WindowsLogPath)) {
        New-Item -ItemType Directory -Path $script:WindowsLogPath -Force | Out-Null
    }
    if (-not (Test-Path $script:MediaLogPath)) {
        New-Item -ItemType Directory -Path $script:MediaLogPath -Force | Out-Null
    }

    # Limpiar logs antiguos
    $retentionDays = [int]($LogRetention -replace 'd','')
    if ($script:WindowsLogPath) {
        Get-ChildItem -Path $script:WindowsLogPath -Filter "*.log" | 
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) } |
            Remove-Item -Force
    }
    Get-ChildItem -Path $script:MediaLogPath -Filter "*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) } |
        Remove-Item -Force

    # Inicializar buffer de logs
    $script:LogBuffer = @()
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Module = "System"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Level][$Module] $Message"
    
    # Añadir al buffer
    $script:LogBuffer += $logMessage
    
    # Escribir a archivos
    $logFiles = @()
    
    # Archivo de sesión
    $sessionLog = "session.log"
    if ($script:WindowsLogPath) {
        $logFiles += Join-Path $script:WindowsLogPath $sessionLog
    }
    $logFiles += Join-Path $script:MediaLogPath $sessionLog
    
    # Archivo específico del módulo
    $moduleLog = "$($Module.ToLower()).log"
    if ($script:WindowsLogPath) {
        $logFiles += Join-Path $script:WindowsLogPath $moduleLog
    }
    $logFiles += Join-Path $script:MediaLogPath $moduleLog
    
    # Escribir a todos los archivos
    foreach ($logFile in $logFiles) {
        try {
            Add-Content -Path $logFile -Value $logMessage -ErrorAction Stop
        } catch {
            # Si falla la escritura, mantener en buffer
            Write-Host "Error al escribir log en $logFile: $_" -ForegroundColor Red
        }
    }

    # Mostrar en consola si es error o warning
    if ($Level -in @("ERROR", "WARNING")) {
        Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } else { "Yellow" })
    }
}

function Flush-LogBuffer {
    # Intentar escribir logs pendientes
    foreach ($logMessage in $script:LogBuffer) {
        $logFiles = @()
        if ($script:WindowsLogPath) {
            $logFiles += Join-Path $script:WindowsLogPath "session.log"
        }
        $logFiles += Join-Path $script:MediaLogPath "session.log"
        
        foreach ($logFile in $logFiles) {
            try {
                Add-Content -Path $logFile -Value $logMessage -ErrorAction Stop
            } catch {
                Write-Host "Error al escribir log pendiente en $logFile: $_" -ForegroundColor Red
            }
        }
    }
    $script:LogBuffer = @()
}

# Registrar función para ejecutar al cerrar
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Flush-LogBuffer } 