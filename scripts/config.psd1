@{
    # Configuración general
    Version = "1.0.0"
    LogRetentionDays = 7
    LogLevel = "INFO"
    
    # Configuración de unidades
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
        }
        Verify = @{
            Enabled = $true
            Priority = 3
            EFIPath = "M:\EFI\Microsoft\Boot"
        }
    }
    
    # Configuración de logging
    Logging = @{
        Path = "..\logs"
        Files = @{
            Session = "session.log"
            Diagnosis = "diagnosis.log"
            BootRepair = "bootrepair.log"
            Verify = "verify.log"
        }
        Levels = @("INFO", "WARNING", "ERROR")
    }
} 