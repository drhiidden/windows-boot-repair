#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet("Full", "Diagnosis", "BootRepair", "Verify")]
    [string]$Mode = "Full",
    
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.psd1"),
    
    [Parameter()]
    [string]$EFIDriveLetter = "",
    
    [Parameter()]
    [string]$SystemDrive = "C",
    
    [Parameter()]
    [switch]$NoLogging,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$SimulationMode,
    
    [Parameter()]
    [switch]$ConfirmExecution,
    
    [Parameter()]
    [switch]$BackupBeforeExecution
)

# Variables globales para control de estado
$script:ExecutionState = @{
    "StartTime" = Get-Date
    "Errors" = @()
    "Warnings" = @()
    "CurrentPhase" = "Inicialización"
    "BackupCreated" = $false
    "BackupPath" = ""
    "EnvironmentVerified" = $false
    "DiagnosisCompleted" = $false
    "RepairCompleted" = $false
    "VerifyCompleted" = $false
    "IsWinPE" = $false
    "IsUEFI" = $false
    "IsLegacyBIOS" = $false
    "SystemDriveExists" = $false
    "EFIPartitionExists" = $false
    "BCDFileExists" = $false
}

# Función para verificar y elevar privilegios
function Test-AdminPrivileges {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Función para elevar privilegios
function Start-ElevatedProcess {
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = $MyInvocation.BoundParameters.GetEnumerator() | 
        ForEach-Object { "-$($_.Key) $($_.Value)" }
    
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments" -Verb RunAs
    exit
}

# Verificar privilegios de administrador
if (-not (Test-AdminPrivileges)) {
    Write-Warning "Se requieren privilegios de administrador. Intentando elevar..."
    Start-ElevatedProcess
}

# Función para confirmar ejecución
function Test-ExecutionConfirmation {
    if (-not $ConfirmExecution) {
        Write-Warning "¡ADVERTENCIA! Este script realizará cambios en el sistema."
        Write-Warning "Para ejecutar en modo real, use el parámetro -ConfirmExecution"
        Write-Warning "Para ejecutar en modo simulación, use el parámetro -SimulationMode"
        return $false
    }
    return $true
}

# Función para crear backup del sistema
function Start-SystemBackup {
    if ($SimulationMode) {
        Write-Log "SIMULACIÓN: Creando backup del sistema" -Module "Backup"
        $script:ExecutionState.BackupCreated = $true
        $script:ExecutionState.BackupPath = "C:\Backup_Simulation"
        return $true
    }
    
    Write-Log "Iniciando backup del sistema" -Module "Backup"
    
    # Crear directorio de backup
    $backupDir = Join-Path $env:SystemDrive "WindowsBootRepairMCP_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    try {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-Log "Directorio de backup creado: $backupDir" -Module "Backup"
        
        # Backup de archivos críticos
        $criticalFiles = @(
            "$env:SystemRoot\Boot\BCD",
            "$env:SystemRoot\Boot\bootstat.dat",
            "$env:SystemRoot\System32\config\SYSTEM",
            "$env:SystemRoot\System32\config\SOFTWARE"
        )
        
        foreach ($file in $criticalFiles) {
            if (Test-Path $file) {
                $destFile = Join-Path $backupDir (Split-Path $file -Leaf)
                Copy-Item -Path $file -Destination $destFile -Force
                Write-Log "Backup creado: $file -> $destFile" -Module "Backup"
            } else {
                Write-Log "Archivo no encontrado para backup: $file" -Level "WARNING" -Module "Backup"
            }
        }
        
        # Backup de configuración EFI
        $efiPath = "$env:SystemDrive\EFI"
        if (Test-Path $efiPath) {
            $efiBackupPath = Join-Path $backupDir "EFI"
            Copy-Item -Path $efiPath -Destination $efiBackupPath -Recurse -Force
            Write-Log "Backup de EFI creado: $efiBackupPath" -Module "Backup"
        }
        
        # Exportar configuración BCD
        $bcdExportPath = Join-Path $backupDir "bcd_export.txt"
        & bcdedit /export $bcdExportPath | Out-Null
        Write-Log "Exportación BCD guardada: $bcdExportPath" -Module "Backup"
        
        $script:ExecutionState.BackupCreated = $true
        $script:ExecutionState.BackupPath = $backupDir
        Write-Log "Backup completado exitosamente" -Module "Backup"
        return $true
    } catch {
        $script:ExecutionState.Errors += "Error al crear backup: $_"
        Write-Log "Error al crear backup: $_" -Level "ERROR" -Module "Backup"
        return $false
    }
}

# Función para restaurar backup
function Restore-SystemBackup {
    if ($SimulationMode) {
        Write-Log "SIMULACIÓN: Restaurando backup del sistema" -Module "Backup"
        return $true
    }
    
    if (-not $script:ExecutionState.BackupCreated) {
        Write-Log "No hay backup disponible para restaurar" -Level "ERROR" -Module "Backup"
        return $false
    }
    
    Write-Log "Iniciando restauración desde backup" -Module "Backup"
    $backupDir = $script:ExecutionState.BackupPath
    
    try {
        # Restaurar archivos críticos
        $criticalFiles = @(
            "$env:SystemRoot\Boot\BCD",
            "$env:SystemRoot\Boot\bootstat.dat",
            "$env:SystemRoot\System32\config\SYSTEM",
            "$env:SystemRoot\System32\config\SOFTWARE"
        )
        
        foreach ($file in $criticalFiles) {
            $backupFile = Join-Path $backupDir (Split-Path $file -Leaf)
            if (Test-Path $backupFile) {
                Copy-Item -Path $backupFile -Destination $file -Force
                Write-Log "Archivo restaurado: $backupFile -> $file" -Module "Backup"
            }
        }
        
        # Restaurar configuración EFI
        $efiBackupPath = Join-Path $backupDir "EFI"
        if (Test-Path $efiBackupPath) {
            $efiPath = "$env:SystemDrive\EFI"
            Copy-Item -Path $efiBackupPath -Destination $efiPath -Recurse -Force
            Write-Log "Configuración EFI restaurada" -Module "Backup"
        }
        
        # Restaurar configuración BCD
        $bcdExportPath = Join-Path $backupDir "bcd_export.txt"
        if (Test-Path $bcdExportPath) {
            & bcdedit /import $bcdExportPath | Out-Null
            Write-Log "Configuración BCD restaurada" -Module "Backup"
        }
        
        Write-Log "Restauración completada exitosamente" -Module "Backup"
        return $true
    } catch {
        $script:ExecutionState.Errors += "Error al restaurar backup: $_"
        Write-Log "Error al restaurar backup: $_" -Level "ERROR" -Module "Backup"
        return $false
    }
}

# Cargar configuración
try {
    if ($SimulationMode) {
        $ConfigPath = (Join-Path $PSScriptRoot "config.test.psd1")
        Write-Warning "Ejecutando en MODO SIMULACIÓN usando configuración de prueba"
    }
    $config = Import-PowerShellDataFile -Path $ConfigPath -ErrorAction Stop
    Write-Verbose "Configuración cargada desde $ConfigPath"
} catch {
    Write-Error "Error al cargar la configuración: $_"
    exit 1
}

# Override de configuración con parámetros
if ($EFIDriveLetter -ne "") {
    $config.Modules.BootRepair.DiskpartScript = $config.Modules.BootRepair.DiskpartScript -replace "assign letter=M", "assign letter=$EFIDriveLetter"
    $config.Modules.Verify.EFIPath = $config.Modules.Verify.EFIPath -replace "M:", "$EFIDriveLetter`:"
}

if ($SystemDrive) {
    $config.SystemDrive = $SystemDrive
    $config.WindowsPath = "$SystemDrive`:\Windows"
    $config.Modules.Diagnosis.SfcParams = $config.Modules.Diagnosis.SfcParams -replace "C:", "$SystemDrive`:"
}

# Configuración de logging
$script:LogPath = Join-Path $PSScriptRoot $config.Logging.Path
$script:LogLevel = $config.LogLevel
$script:LogRetention = "$($config.LogRetentionDays)d"

# Función de Logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Module = "System"
    )
    
    if ($NoLogging) { return }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp][$Level][$Module] $Message"
    
    # Escribir a archivo
    $logFile = Join-Path $LogPath $config.Logging.Files.Session
    Add-Content -Path $logFile -Value $logMessage

    # Mostrar en consola si es error o warning
    if ($Level -in @("ERROR", "WARNING")) {
        Write-Host $logMessage -ForegroundColor $(if ($Level -eq "ERROR") { "Red" } else { "Yellow" })
    }
}

# Función para verificar entorno
function Test-Environment {
    Write-Log "Verificando entorno de ejecución" -Module "Environment"
    $script:ExecutionState.CurrentPhase = "Verificación de Entorno"
    
    # Verificar si estamos en WinPE
    $script:ExecutionState.IsWinPE = $env:SystemDrive -eq "X:"
    Write-Log "Entorno: $(if ($script:ExecutionState.IsWinPE) { 'WinPE' } else { 'Windows' })" -Module "Environment"
    
    # Verificar versión de PowerShell
    $psVersion = $PSVersionTable.PSVersion
    Write-Log "Versión de PowerShell: $psVersion" -Module "Environment"
    
    # Verificar tipo de BIOS (UEFI o Legacy)
    $firmwareType = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
    if ($firmwareType) {
        $script:ExecutionState.IsUEFI = $firmwareType.BIOSCharacteristics -contains 12
        $script:ExecutionState.IsLegacyBIOS = -not $script:ExecutionState.IsUEFI
        Write-Log "Tipo de firmware: $(if ($script:ExecutionState.IsUEFI) { 'UEFI' } else { 'Legacy BIOS' })" -Module "Environment"
    } else {
        Write-Log "No se pudo determinar el tipo de firmware" -Level "WARNING" -Module "Environment"
    }
    
    # Verificar unidad del sistema
    $systemDrivePath = "$($config.SystemDrive):"
    $script:ExecutionState.SystemDriveExists = Test-Path $systemDrivePath
    Write-Log "Unidad del sistema ($systemDrivePath): $(if ($script:ExecutionState.SystemDriveExists) { 'Disponible' } else { 'No disponible' })" -Module "Environment"
    
    # Verificar partición EFI
    $efiPath = "$($config.SystemDrive):\EFI"
    $script:ExecutionState.EFIPartitionExists = Test-Path $efiPath
    Write-Log "Partición EFI ($efiPath): $(if ($script:ExecutionState.EFIPartitionExists) { 'Disponible' } else { 'No disponible' })" -Module "Environment"
    
    # Verificar archivo BCD
    $bcdPath = "$($config.SystemDrive):\Boot\BCD"
    $script:ExecutionState.BCDFileExists = Test-Path $bcdPath
    Write-Log "Archivo BCD ($bcdPath): $(if ($script:ExecutionState.BCDFileExists) { 'Disponible' } else { 'No disponible' })" -Module "Environment"
    
    # Verificar comandos necesarios
    $requiredCommands = @("chkdsk", "sfc", "DISM", "bootrec", "bcdedit", "diskpart")
    $missingCommands = @()
    
    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missingCommands += $cmd
        }
    }
    
    if ($missingCommands.Count -gt 0) {
        Write-Log "Comandos faltantes: $($missingCommands -join ', ')" -Level "WARNING" -Module "Environment"
        if (-not $Force) {
            Write-Log "Ejecución abortada debido a comandos faltantes" -Level "ERROR" -Module "Environment"
            return $false
        }
    }
    
    $script:ExecutionState.EnvironmentVerified = $true
    return $true
}

# Función de Diagnóstico
function Start-Diagnosis {
    Write-Log "Iniciando diagnóstico del sistema" -Module "Diagnosis"
    $script:ExecutionState.CurrentPhase = "Diagnóstico"
    
    if ($config.Modules.Diagnosis.SimulationMode -or $SimulationMode) {
        Write-Log "SIMULACIÓN: Ejecutando chkdsk en $($config.SystemDrive):" -Module "Diagnosis"
        Write-Log "SIMULACIÓN: Verificando estado SMART" -Module "Diagnosis"
        Write-Log "SIMULACIÓN: Ejecutando SFC" -Module "Diagnosis"
        Write-Log "SIMULACIÓN: Ejecutando DISM" -Module "Diagnosis"
        $script:ExecutionState.DiagnosisCompleted = $true
        return $true
    }
    
    # Verificar disco C:
    Write-Log "Ejecutando chkdsk en $($config.SystemDrive):" -Module "Diagnosis"
    $chkdskOutput = Join-Path $LogPath $config.Logging.Files.Diagnosis
    $chkdskParams = $config.Modules.Diagnosis.ChkdskParams
    
    try {
        & chkdsk "$($config.SystemDrive):" $chkdskParams | Out-File -FilePath $chkdskOutput -Append
        Write-Log "Chkdsk completado" -Module "Diagnosis"
    } catch {
        $script:ExecutionState.Errors += "Error al ejecutar chkdsk: $_"
        Write-Log "Error al ejecutar chkdsk: $_" -Level "ERROR" -Module "Diagnosis"
        if (-not $Force) { return $false }
    }
    
    # Verificar estado SMART
    Write-Log "Verificando estado SMART de los discos" -Module "Diagnosis"
    try {
        $smartStatus = wmic diskdrive get status
        Add-Content -Path $chkdskOutput -Value "`nEstado SMART:"
        Add-Content -Path $chkdskOutput -Value $smartStatus
        
        # Verificar si hay errores SMART
        if ($smartStatus -match "Error|error|ERROR") {
            $script:ExecutionState.Warnings += "Se detectaron errores SMART en los discos"
            Write-Log "Se detectaron errores SMART en los discos" -Level "WARNING" -Module "Diagnosis"
        }
    } catch {
        $script:ExecutionState.Warnings += "Error al verificar estado SMART: $_"
        Write-Log "Error al verificar estado SMART: $_" -Level "WARNING" -Module "Diagnosis"
    }
    
    # Verificar integridad del sistema
    Write-Log "Ejecutando SFC" -Module "Diagnosis"
    $sfcParams = $config.Modules.Diagnosis.SfcParams
    try {
        & sfc $sfcParams | Out-File -FilePath $chkdskOutput -Append
        Write-Log "SFC completado" -Module "Diagnosis"
    } catch {
        $script:ExecutionState.Errors += "Error al ejecutar SFC: $_"
        Write-Log "Error al ejecutar SFC: $_" -Level "ERROR" -Module "Diagnosis"
        if (-not $Force) { return $false }
    }
    
    # Verificar imagen del sistema
    Write-Log "Ejecutando DISM" -Module "Diagnosis"
    $dismParams = $config.Modules.Diagnosis.DismParams
    try {
        & DISM /Image:"$($config.SystemDrive):" $dismParams | Out-File -FilePath $chkdskOutput -Append
        Write-Log "DISM completado" -Module "Diagnosis"
    } catch {
        $script:ExecutionState.Errors += "Error al ejecutar DISM: $_"
        Write-Log "Error al ejecutar DISM: $_" -Level "ERROR" -Module "Diagnosis"
        if (-not $Force) { return $false }
    }
    
    $script:ExecutionState.DiagnosisCompleted = $true
    return $true
}

# Función de Reparación
function Start-BootRepair {
    Write-Log "Iniciando reparación del gestor de arranque" -Module "BootRepair"
    $script:ExecutionState.CurrentPhase = "Reparación"
    
    if ($config.Modules.BootRepair.SimulationMode -or $SimulationMode) {
        Write-Log "SIMULACIÓN: Asignando letra a la partición EFI" -Module "BootRepair"
        Write-Log "SIMULACIÓN: Reparando sector de arranque" -Module "BootRepair"
        Write-Log "SIMULACIÓN: Reconstruyendo BCD" -Module "BootRepair"
        Write-Log "SIMULACIÓN: Configurando arranque UEFI" -Module "BootRepair"
        $script:ExecutionState.RepairCompleted = $true
        return $true
    }
    
    $bootrepairLog = Join-Path $LogPath $config.Logging.Files.BootRepair
    
    # Verificar si es necesario reparar
    if (-not $script:ExecutionState.EFIPartitionExists -and -not $script:ExecutionState.BCDFileExists) {
        Write-Log "No se detectaron archivos de arranque. Se requiere reparación completa." -Level "WARNING" -Module "BootRepair"
    } elseif (-not $script:ExecutionState.EFIPartitionExists) {
        Write-Log "No se detectó partición EFI. Se requiere reparación de EFI." -Level "WARNING" -Module "BootRepair"
    } elseif (-not $script:ExecutionState.BCDFileExists) {
        Write-Log "No se detectó archivo BCD. Se requiere reparación de BCD." -Level "WARNING" -Module "BootRepair"
    }
    
    # Asignar letra a la partición EFI
    Write-Log "Asignando letra a la partición EFI" -Module "BootRepair"
    $diskpartScript = $config.Modules.BootRepair.DiskpartScript
    
    try {
        $diskpartScript | diskpart | Out-File -FilePath $bootrepairLog -Append
        Write-Log "Letra asignada a la partición EFI" -Module "BootRepair"
    } catch {
        $script:ExecutionState.Errors += "Error al ejecutar diskpart: $_"
        Write-Log "Error al ejecutar diskpart: $_" -Level "ERROR" -Module "BootRepair"
        if (-not $Force) { return $false }
    }
    
    # Reparar sector de arranque
    Write-Log "Reparando sector de arranque" -Module "BootRepair"
    try {
        & bootrec /fixmbr | Out-File -FilePath $bootrepairLog -Append
        & bootrec /fixboot | Out-File -FilePath $bootrepairLog -Append
        Write-Log "Sector de arranque reparado" -Module "BootRepair"
    } catch {
        $script:ExecutionState.Errors += "Error al reparar sector de arranque: $_"
        Write-Log "Error al reparar sector de arranque: $_" -Level "ERROR" -Module "BootRepair"
        if (-not $Force) { return $false }
    }
    
    # Reconstruir BCD
    Write-Log "Reconstruyendo BCD" -Module "BootRepair"
    try {
        & bootrec /scanos | Out-File -FilePath $bootrepairLog -Append
        & bootrec /rebuildbcd | Out-File -FilePath $bootrepairLog -Append
        Write-Log "BCD reconstruido" -Module "BootRepair"
    } catch {
        $script:ExecutionState.Errors += "Error al reconstruir BCD: $_"
        Write-Log "Error al reconstruir BCD: $_" -Level "ERROR" -Module "BootRepair"
        if (-not $Force) { return $false }
    }
    
    # Configurar arranque UEFI
    if ($script:ExecutionState.IsUEFI) {
        Write-Log "Configurando arranque UEFI" -Module "BootRepair"
        $efiDrive = $config.Modules.Verify.EFIPath.Split(":")[0]
        try {
            & bcdboot "$($config.WindowsPath)" /s "$efiDrive`:" /f UEFI | Out-File -FilePath $bootrepairLog -Append
            Write-Log "Arranque UEFI configurado" -Module "BootRepair"
        } catch {
            $script:ExecutionState.Errors += "Error al configurar arranque UEFI: $_"
            Write-Log "Error al configurar arranque UEFI: $_" -Level "ERROR" -Module "BootRepair"
            if (-not $Force) { return $false }
        }
    } else {
        Write-Log "Sistema no es UEFI, omitiendo configuración UEFI" -Module "BootRepair"
    }
    
    $script:ExecutionState.RepairCompleted = $true
    return $true
}

# Función de Verificación
function Start-Verify {
    Write-Log "Iniciando verificación final del sistema" -Module "Verify"
    $script:ExecutionState.CurrentPhase = "Verificación"
    
    if ($config.Modules.Verify.SimulationMode -or $SimulationMode) {
        Write-Log "SIMULACIÓN: Verificando archivos EFI" -Module "Verify"
        Write-Log "SIMULACIÓN: Verificando configuración BCD" -Module "Verify"
        $script:ExecutionState.VerifyCompleted = $true
        return @{
            "EFIFiles" = $true
            "BCDConfig" = $true
            "BootStatus" = $true
        }
    }
    
    $verifyResults = @{
        "EFIFiles" = $true
        "BCDConfig" = $true
        "BootStatus" = $true
    }
    
    $verifyLog = Join-Path $LogPath $config.Logging.Files.Verify
    
    # Verificar archivos EFI
    Write-Log "Verificando archivos EFI" -Module "Verify"
    $efiPath = $config.Modules.Verify.EFIPath
    if (Test-Path $efiPath) {
        $efiFiles = Get-ChildItem -Path $efiPath -File
        foreach ($file in $efiFiles) {
            if (-not (Test-Path $file.FullName)) {
                $verifyResults.EFIFiles = $false
                Write-Log "Archivo EFI faltante: $($file.Name)" -Level "WARNING" -Module "Verify"
            }
        }
    } else {
        $verifyResults.EFIFiles = $false
        Write-Log "Directorio EFI no encontrado" -Level "ERROR" -Module "Verify"
    }
    
    # Verificar configuración BCD
    Write-Log "Verificando configuración BCD" -Module "Verify"
    try {
        $bcdOutput = & bcdedit /enum
        $bcdOutput | Out-File -FilePath $verifyLog -Append
        
        if ($bcdOutput -match "error|Error|ERROR") {
            $verifyResults.BCDConfig = $false
            Write-Log "Problemas detectados en la configuración BCD" -Level "WARNING" -Module "Verify"
        }
    } catch {
        $verifyResults.BCDConfig = $false
        Write-Log "Error al verificar BCD: $_" -Level "ERROR" -Module "Verify"
    }
    
    # Verificar estado de arranque
    Write-Log "Verificando estado de arranque" -Module "Verify"
    try {
        $bootStatus = & bcdedit /enum {bootmgr}
        $bootStatus | Out-File -FilePath $verifyLog -Append
        
        if ($bootStatus -match "error|Error|ERROR") {
            $verifyResults.BootStatus = $false
            Write-Log "Problemas detectados en el estado de arranque" -Level "WARNING" -Module "Verify"
        }
    } catch {
        $verifyResults.BootStatus = $false
        Write-Log "Error al verificar estado de arranque: $_" -Level "ERROR" -Module "Verify"
    }
    
    # Generar reporte final
    "=== Reporte de Verificación Final ===" | Out-File -FilePath $verifyLog
    "Fecha: $(Get-Date)" | Out-File -FilePath $verifyLog -Append
    "Estado EFI: $($verifyResults.EFIFiles)" | Out-File -FilePath $verifyLog -Append
    "Estado BCD: $($verifyResults.BCDConfig)" | Out-File -FilePath $verifyLog -Append
    "Estado Arranque: $($verifyResults.BootStatus)" | Out-File -FilePath $verifyLog -Append
    
    $script:ExecutionState.VerifyCompleted = $true
    return $verifyResults
}

# Función para generar reporte final
function Write-ExecutionReport {
    $reportPath = Join-Path $LogPath "execution_report.txt"
    
    "=== REPORTE DE EJECUCIÓN - WindowsBootRepairMCP ===" | Out-File -FilePath $reportPath
    "Fecha: $(Get-Date)" | Out-File -FilePath $reportPath -Append
    "Duración: $((Get-Date).Subtract($script:ExecutionState.StartTime).ToString())" | Out-File -FilePath $reportPath -Append
    "" | Out-File -FilePath $reportPath -Append
    
    "ESTADO DEL ENTORNO:" | Out-File -FilePath $reportPath -Append
    "- WinPE: $($script:ExecutionState.IsWinPE)" | Out-File -FilePath $reportPath -Append
    "- UEFI: $($script:ExecutionState.IsUEFI)" | Out-File -FilePath $reportPath -Append
    "- Legacy BIOS: $($script:ExecutionState.IsLegacyBIOS)" | Out-File -FilePath $reportPath -Append
    "- Unidad del sistema: $($script:ExecutionState.SystemDriveExists)" | Out-File -FilePath $reportPath -Append
    "- Partición EFI: $($script:ExecutionState.EFIPartitionExists)" | Out-File -FilePath $reportPath -Append
    "- Archivo BCD: $($script:ExecutionState.BCDFileExists)" | Out-File -FilePath $reportPath -Append
    "" | Out-File -FilePath $reportPath -Append
    
    "ESTADO DE LA EJECUCIÓN:" | Out-File -FilePath $reportPath -Append
    "- Entorno verificado: $($script:ExecutionState.EnvironmentVerified)" | Out-File -FilePath $reportPath -Append
    "- Diagnóstico completado: $($script:ExecutionState.DiagnosisCompleted)" | Out-File -FilePath $reportPath -Append
    "- Reparación completada: $($script:ExecutionState.RepairCompleted)" | Out-File -FilePath $reportPath -Append
    "- Verificación completada: $($script:ExecutionState.VerifyCompleted)" | Out-File -FilePath $reportPath -Append
    "" | Out-File -FilePath $reportPath -Append
    
    if ($script:ExecutionState.BackupCreated) {
        "BACKUP:" | Out-File -FilePath $reportPath -Append
        "- Backup creado: Sí" | Out-File -FilePath $reportPath -Append
        "- Ruta de backup: $($script:ExecutionState.BackupPath)" | Out-File -FilePath $reportPath -Append
        "" | Out-File -FilePath $reportPath -Append
    }
    
    if ($script:ExecutionState.Warnings.Count -gt 0) {
        "ADVERTENCIAS:" | Out-File -FilePath $reportPath -Append
        foreach ($warning in $script:ExecutionState.Warnings) {
            "- $warning" | Out-File -FilePath $reportPath -Append
        }
        "" | Out-File -FilePath $reportPath -Append
    }
    
    if ($script:ExecutionState.Errors.Count -gt 0) {
        "ERRORES:" | Out-File -FilePath $reportPath -Append
        foreach ($error in $script:ExecutionState.Errors) {
            "- $error" | Out-File -FilePath $reportPath -Append
        }
        "" | Out-File -FilePath $reportPath -Append
    }
    
    "RECOMENDACIONES:" | Out-File -FilePath $reportPath -Append
    if ($script:ExecutionState.Errors.Count -gt 0) {
        "- Se detectaron errores durante la ejecución. Revise los logs para más detalles." | Out-File -FilePath $reportPath -Append
    }
    if (-not $script:ExecutionState.VerifyCompleted) {
        "- La verificación no se completó. Se recomienda ejecutar el script nuevamente con el parámetro -Mode Verify." | Out-File -FilePath $reportPath -Append
    }
    if (-not $script:ExecutionState.EFIPartitionExists) {
        "- No se detectó partición EFI. Verifique la configuración del sistema." | Out-File -FilePath $reportPath -Append
    }
    if (-not $script:ExecutionState.BCDFileExists) {
        "- No se detectó archivo BCD. Verifique la configuración del sistema." | Out-File -FilePath $reportPath -Append
    }
    
    Write-Log "Reporte de ejecución generado: $reportPath" -Module "Report"
    return $reportPath
}

# Función Principal
function Start-Repair {
    # Crear directorio de logs si no existe
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath | Out-Null
    }
    
    Write-Log "Iniciando proceso de reparación" -Module "Main"
    
    # Verificar confirmación de ejecución
    if (-not (Test-ExecutionConfirmation)) {
        Write-Log "Ejecución cancelada por falta de confirmación" -Level "WARNING" -Module "Main"
        return $false
    }
    
    # Crear backup si se solicita
    if ($BackupBeforeExecution -and -not $SimulationMode) {
        if (-not (Start-SystemBackup)) {
            Write-Log "Error al crear backup. Abortando ejecución." -Level "ERROR" -Module "Main"
            return $false
        }
    }
    
    # Verificar entorno
    if (-not (Test-Environment)) {
        Write-Log "Verificación de entorno fallida" -Level "ERROR" -Module "Main"
        return $false
    }
    
    # Ejecutar módulos según el modo
    $success = $true
    
    if ($Mode -in @("Full", "Diagnosis")) {
        if (-not (Start-Diagnosis)) {
            Write-Log "Error en el diagnóstico" -Level "ERROR" -Module "Main"
            $success = $false
            if (-not $Force) { 
                if ($script:ExecutionState.BackupCreated) {
                    Write-Log "Restaurando backup debido a error en diagnóstico" -Level "WARNING" -Module "Main"
                    Restore-SystemBackup
                }
                return $false 
            }
        }
    }
    
    if ($Mode -in @("Full", "BootRepair")) {
        if (-not (Start-BootRepair)) {
            Write-Log "Error en la reparación" -Level "ERROR" -Module "Main"
            $success = $false
            if (-not $Force) { 
                if ($script:ExecutionState.BackupCreated) {
                    Write-Log "Restaurando backup debido a error en reparación" -Level "WARNING" -Module "Main"
                    Restore-SystemBackup
                }
                return $false 
            }
        }
    }
    
    if ($Mode -in @("Full", "Verify")) {
        $verifyResults = Start-Verify
        if (-not ($verifyResults.EFIFiles -and $verifyResults.BCDConfig)) {
            Write-Log "Problemas detectados en la verificación" -Level "WARNING" -Module "Main"
            $success = $false
        }
    }
    
    # Generar reporte final
    $reportPath = Write-ExecutionReport
    
    Write-Log "Proceso de reparación completado" -Module "Main"
    Write-Log "Reporte generado: $reportPath" -Module "Main"
    
    if (-not $success) {
        Write-Log "Se detectaron problemas durante la ejecución. Revise el reporte para más detalles." -Level "WARNING" -Module "Main"
    }
    
    return $success
}

# Ejecutar reparación
Start-Repair 