# Módulo de Verificación Final
function Start-FinalVerifyModule {
    Write-Log "Iniciando verificación final del sistema" -Module "FinalVerify"
    
    $verifyResults = @{
        "EFIFiles" = $true
        "BCDConfig" = $true
        "BootStatus" = $true
    }
    
    # Verificar archivos EFI
    Write-Log "Verificando archivos EFI" -Module "FinalVerify"
    $efiPath = "M:\EFI\Microsoft\Boot"
    if (Test-Path $efiPath) {
        $efiFiles = Get-ChildItem -Path $efiPath -File
        foreach ($file in $efiFiles) {
            if (-not (Test-Path $file.FullName)) {
                $verifyResults.EFIFiles = $false
                Write-Log "Archivo EFI faltante: $($file.Name)" -Level "WARNING" -Module "FinalVerify"
            }
        }
    } else {
        $verifyResults.EFIFiles = $false
        Write-Log "Directorio EFI no encontrado" -Level "ERROR" -Module "FinalVerify"
    }
    
    # Verificar configuración BCD
    Write-Log "Verificando configuración BCD" -Module "FinalVerify"
    $bcdOutput = bcdedit /enum
    if ($bcdOutput -match "error|Error|ERROR") {
        $verifyResults.BCDConfig = $false
        Write-Log "Problemas detectados en la configuración BCD" -Level "WARNING" -Module "FinalVerify"
    }
    
    # Verificar estado de arranque
    Write-Log "Verificando estado de arranque" -Module "FinalVerify"
    $bootStatus = Get-WmiObject -Class Win32_OperatingSystem
    if ($bootStatus.LastBootUpTime -eq $null) {
        $verifyResults.BootStatus = $false
        Write-Log "No se pudo obtener información del último arranque" -Level "WARNING" -Module "FinalVerify"
    }
    
    # Generar reporte final
    $reportPath = Join-Path $LogPath "final_verify.log"
    "=== Reporte de Verificación Final ===" | Out-File -FilePath $reportPath
    "Fecha: $(Get-Date)" | Out-File -FilePath $reportPath -Append
    "Estado EFI: $($verifyResults.EFIFiles)" | Out-File -FilePath $reportPath -Append
    "Estado BCD: $($verifyResults.BCDConfig)" | Out-File -FilePath $reportPath -Append
    "Estado Arranque: $($verifyResults.BootStatus)" | Out-File -FilePath $reportPath -Append
    
    Write-Log "Verificación final completada" -Module "FinalVerify"
    return $verifyResults
} 