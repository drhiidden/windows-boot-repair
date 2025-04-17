@{
    # Configuración general
    Version = "1.0.0-test"
    LogRetentionDays = 1
    LogLevel = "DEBUG"
    
    # Configuración de unidades (simuladas)
    EFIDriveLetter = "M"
    SystemDrive = "C"
    WindowsPath = "C:\Windows"
    
    # Configuración de módulos
    Modules = @{
        Diagnosis = @{
            Enabled = $true
            Priority = 1
            ChkdskParams = "/f /r /x"
            SfcParams = "/scannow /offbootdir=C:\ /offwindir=C:\Windows"
            DismParams = "/Cleanup-Image /RestoreHealth"
            # Modo simulación
            SimulationMode = $true
        }
        BootRepair = @{
            Enabled = $true
            Priority = 2
            DiskpartScript = @"
list disk
select disk 0
list partition
select partition 1
assign letter=M
exit
"@
            # Modo simulación
            SimulationMode = $true
        }
        Verify = @{
            Enabled = $true
            Priority = 3
            EFIPath = "M:\EFI\Microsoft\Boot"
            # Modo simulación
            SimulationMode = $true
        }
    }
    
    # Configuración de logging
    Logging = @{
        Path = "..\logs\test"
        Files = @{
            Session = "test-session.log"
            Diagnosis = "test-diagnosis.log"
            BootRepair = "test-bootrepair.log"
            Verify = "test-verify.log"
        }
        Levels = @("INFO", "WARNING", "ERROR", "DEBUG")
    }
} 