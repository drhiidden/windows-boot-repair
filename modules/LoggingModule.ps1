# Módulo de Logging
$script:LogPath = $null
$script:LogLevel = "INFO"
$script:LogRetention = "7d"
$script:WindowsLogPath = $null
$script:MediaLogPath = $null
$script:LogBuffer = @()

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
        # En WinPE, intentar detectar la unidad de Windows
        $windowsDrive = Get-WmiObject -Class Win32_LogicalDisk | 
            Where-Object { $_.FileSystem -eq "NTFS" -and $_.DeviceID -ne "X:" } |
            Select-Object -First 1 -ExpandProperty DeviceID

        if ($windowsDrive) {
            $script:WindowsLogPath = Join-Path "${windowsDrive}:" "Windows\Logs\WindowsBootRepairMCP"
            $script:MediaLogPath = Join-Path $Config.path "logs"
        } else {
            # Si no se encuentra Windows, usar solo el medio
            $script:MediaLogPath = Join-Path $Config.path "logs"
            $script:WindowsLogPath = $null
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