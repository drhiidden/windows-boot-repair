# Windows Boot Repair MCP

Herramienta de reparación y diagnóstico del gestor de arranque de Windows.

## Descripción

Windows Boot Repair MCP es una herramienta PowerShell diseñada para diagnosticar y reparar problemas relacionados con el gestor de arranque de Windows. La herramienta puede ejecutarse en Windows PE o en un entorno de Windows normal, y proporciona funcionalidades para verificar el estado del sistema, reparar problemas de arranque y generar informes detallados.

## Características

- **Diagnóstico completo**: Verifica el estado del disco, SMART, integridad del sistema y más
- **Reparación de arranque**: Repara MBR, sector de arranque, BCD y configuración UEFI
- **Verificación final**: Comprueba la integridad de los archivos EFI y la configuración BCD
- **Sistema de logging**: Registra todas las operaciones con diferentes niveles de detalle
- **Modo simulación**: Permite probar la herramienta sin realizar cambios reales
- **Backup automático**: Crea copias de seguridad antes de realizar cambios
- **Reportes detallados**: Genera informes completos de la ejecución

## Requisitos

- Windows 10/11 o Windows PE 10/11
- Mínimo 2GB RAM
- Al menos 100MB de espacio en disco
- Privilegios de administrador

## Instalación

### En Windows PE
1. Copiar los archivos a una unidad USB o disco
2. Ejecutar desde la línea de comandos de Windows PE:
   ```powershell
   .\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
   ```

### En Hiren's Boot CD
1. Copiar los archivos a la carpeta `Tools`
2. Ejecutar desde la línea de comandos:
   ```powershell
   .\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
   ```

## Estructura del Proyecto

```
WindowsBootRepairMCP/
├── scripts/
│   ├── repair.ps1           # Script principal
│   ├── test-repair.ps1      # Script de pruebas
│   ├── config.psd1          # Configuración principal
│   └── config.test.psd1     # Configuración de pruebas
├── modules/
│   ├── DiagnosisModule.ps1  # Módulo de diagnóstico
│   ├── BootRepairModule.ps1 # Módulo de reparación
│   ├── FinalVerifyModule.ps1 # Módulo de verificación
│   └── LoggingModule.ps1    # Módulo de logging
├── logs/
│   └── .gitkeep             # Mantiene la estructura del directorio
├── tests/
│   └── README.md            # Documentación de pruebas
└── docs/
    └── README.md            # Documentación detallada
```

## Uso

Para más información sobre cómo usar la herramienta, consulte la [documentación detallada](docs/README.md).

## Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## Seguridad

⚠️ **ADVERTENCIAS IMPORTANTES**:

- El programa requiere confirmación explícita para ejecutar cambios reales
- Se recomienda probar en máquinas virtuales o entornos controlados
- Use `-BackupBeforeExecution` para crear backup automático
- Solo ejecute con `-ConfirmExecution` cuando esté seguro
- Revise los logs para identificar la causa de los errores 