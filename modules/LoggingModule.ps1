# Módulo de Logging
$script:LogPath = $null
$script:LogLevel = "INFO"
$script:LogRetention = "7d"

function Initialize-Logging {
    param (
        [PSCustomObject]$Config
    )
    $script:LogPath = $Config.path
    $script:LogLevel = $Config.level
    $script:LogRetention = $Config.retention

    # Crear directorio de logs si no existe
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath | Out-Null
    }

    # Limpiar logs antiguos
    $retentionDays = [int]($LogRetention -replace 'd','')
    Get-ChildItem -Path $LogPath -Filter "*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) } |
        Remove-Item -Force
}

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Module = "System"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Level][$Module] $Message"
    
    # Escribir a archivo
    $logFile = Join-Path $LogPath "session.log"
    Add-Content -Path $logFile -Value $logMessage

    # Mostrar en consola si es error o warning
    if ($Level -in @("ERROR", "WARNING")) {
        Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } else { "Yellow" })
    }
} 