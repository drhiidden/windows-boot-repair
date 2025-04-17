# Módulo de Reparación de Arranque
function Start-BootRepairModule {
    Write-Log "Iniciando reparación del gestor de arranque" -Module "BootRepair"
    
    $bootrepairLog = Join-Path $LogPath "bootrepair.log"
    
    # Asignar letra a la partición EFI
    Write-Log "Asignando letra a la partición EFI" -Module "BootRepair"
    $diskpartScript = @"
list disk
select disk 0
list partition
select partition 1
assign letter=M
exit
"@
    
    $diskpartScript | diskpart | Out-File -FilePath $bootrepairLog -Append
    
    # Reparar sector de arranque
    Write-Log "Reparando sector de arranque" -Module "BootRepair"
    bootrec /fixmbr | Out-File -FilePath $bootrepairLog -Append
    bootrec /fixboot | Out-File -FilePath $bootrepairLog -Append
    
    # Reconstruir BCD
    Write-Log "Reconstruyendo BCD" -Module "BootRepair"
    bootrec /scanos | Out-File -FilePath $bootrepairLog -Append
    bootrec /rebuildbcd | Out-File -FilePath $bootrepairLog -Append
    
    # Configurar arranque UEFI
    Write-Log "Configurando arranque UEFI" -Module "BootRepair"
    bcdboot C:\Windows /s M: /f UEFI | Out-File -FilePath $bootrepairLog -Append
    
    # Verificar resultados
    $repairResults = @{
        "MBR" = $true
        "BootSector" = $true
        "BCD" = $true
    }
    
    # Analizar resultados
    $logContent = Get-Content $bootrepairLog
    if ($logContent -match "error|Error|ERROR") {
        Write-Log "Se encontraron errores durante la reparación" -Level "WARNING" -Module "BootRepair"
        $repairResults.MBR = $false
        $repairResults.BootSector = $false
        $repairResults.BCD = $false
    }
    
    Write-Log "Reparación de arranque completada" -Module "BootRepair"
    return $repairResults
} 