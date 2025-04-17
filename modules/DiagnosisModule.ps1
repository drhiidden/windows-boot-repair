# Módulo de Diagnóstico
function Start-DiagnosisModule {
    Write-Log "Iniciando diagnóstico del sistema" -Module "Diagnosis"
    
    # Verificar disco C:
    Write-Log "Ejecutando chkdsk en C:" -Module "Diagnosis"
    $chkdskOutput = Join-Path $LogPath "diagnosis_output.log"
    chkdsk C: /f /r /x | Out-File -FilePath $chkdskOutput -Append
    
    # Verificar estado SMART
    Write-Log "Verificando estado SMART de los discos" -Module "Diagnosis"
    $smartStatus = wmic diskdrive get status
    Add-Content -Path $chkdskOutput -Value "`nEstado SMART:"
    Add-Content -Path $chkdskOutput -Value $smartStatus
    
    # Verificar integridad del sistema
    Write-Log "Ejecutando SFC" -Module "Diagnosis"
    sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows | Out-File -FilePath $chkdskOutput -Append
    
    # Verificar imagen del sistema
    Write-Log "Ejecutando DISM" -Module "Diagnosis"
    DISM /Image:C:\ /Cleanup-Image /RestoreHealth | Out-File -FilePath $chkdskOutput -Append
    
    # Analizar resultados
    $diagnosisResults = @{
        "Chkdsk" = $true
        "SMART" = $true
        "SFC" = $true
        "DISM" = $true
    }
    
    # Verificar resultados de chkdsk
    $chkdskContent = Get-Content $chkdskOutput
    if ($chkdskContent -match "error|Error|ERROR") {
        $diagnosisResults.Chkdsk = $false
        Write-Log "Se encontraron errores en chkdsk" -Level "WARNING" -Module "Diagnosis"
    }
    
    # Verificar estado SMART
    if ($smartStatus -match "Error|Pred Fail") {
        $diagnosisResults.SMART = $false
        Write-Log "Se detectaron problemas en el estado SMART" -Level "WARNING" -Module "Diagnosis"
    }
    
    Write-Log "Diagnóstico completado" -Module "Diagnosis"
    return $diagnosisResults
} 