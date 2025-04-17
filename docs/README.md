# Windows Boot Repair MCP

Herramienta de reparación y diagnóstico del gestor de arranque de Windows.

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
├── logs/
│   ├── session.log          # Log general
│   ├── diagnosis.log        # Log de diagnóstico
│   ├── bootrepair.log       # Log de reparación
│   ├── verify.log           # Log de verificación
│   ├── execution_report.txt # Reporte detallado de ejecución
│   └── test/                # Logs de pruebas
├── tests/                   # Tests automatizados
└── docs/                    # Documentación
```

## Modos de Ejecución

### 1. Modo Producción
Para ejecutar el programa en un sistema real:
```powershell
.\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
```
⚠️ **IMPORTANTE**: Este modo realizará cambios reales en el sistema. Requiere confirmación explícita.

### 2. Modo Simulación
Para probar el programa sin realizar cambios:
```powershell
.\scripts\repair.ps1 -SimulationMode
```
Este modo simula todas las operaciones y genera logs de prueba.

### 3. Modo Pruebas
Para ejecutar pruebas controladas:
```powershell
.\scripts\test-repair.ps1
```
Verifica el entorno y ejecuta en modo simulación con logs detallados.

## Parámetros Disponibles

- `-Mode`: Modo de operación ("Full", "Diagnosis", "BootRepair", "Verify")
- `-ConfigPath`: Ruta al archivo de configuración
- `-EFIDriveLetter`: Letra para la partición EFI
- `-SystemDrive`: Unidad del sistema (por defecto "C")
- `-NoLogging`: Deshabilita el logging
- `-Force`: Fuerza la ejecución ignorando errores
- `-SimulationMode`: Ejecuta en modo simulación
- `-ConfirmExecution`: Confirma la ejecución en modo producción
- `-BackupBeforeExecution`: Crea un backup antes de ejecutar cambios

## Flujo de Ejecución

El programa sigue un flujo de ejecución estricto para garantizar la seguridad:

1. **Verificación de Entorno**:
   - Comprueba privilegios de administrador
   - Detecta tipo de firmware (UEFI/Legacy)
   - Verifica disponibilidad de unidades y particiones
   - Comprueba existencia de archivos críticos

2. **Backup Preventivo** (opcional):
   - Crea copia de seguridad de archivos críticos
   - Exporta configuración BCD
   - Guarda archivos de configuración del sistema

3. **Diagnóstico**:
   - Ejecuta verificaciones de disco
   - Comprueba estado SMART
   - Verifica integridad del sistema
   - Detecta problemas potenciales

4. **Reparación**:
   - Asigna letra a partición EFI
   - Repara sector de arranque
   - Reconstruye BCD
   - Configura arranque UEFI (si aplica)

5. **Verificación**:
   - Comprueba archivos EFI
   - Verifica configuración BCD
   - Valida estado de arranque

6. **Generación de Reporte**:
   - Crea informe detallado de la ejecución
   - Registra errores y advertencias
   - Proporciona recomendaciones

## Módulos

### Diagnosis.ps1
- Ejecuta `chkdsk` en la unidad del sistema
- Verifica estado SMART de discos
- Ejecuta `sfc` para verificar integridad
- Usa `DISM` para verificar imagen del sistema

### BootRepair.ps1
- Asigna letra a la partición EFI
- Repara MBR y sector de arranque
- Reconstruye BCD
- Configura arranque UEFI

### Verify.ps1
- Verifica archivos EFI
- Comprueba configuración BCD
- Genera reporte de verificación

### Logging.ps1
- Sistema centralizado de logging
- Niveles: INFO, WARNING, ERROR, DEBUG
- Retención configurable de logs
- Logs separados por módulo

## Logs y Reportes

Los logs se almacenan en la carpeta `logs/`:
- `session.log`: Log general de la sesión
- `diagnosis.log`: Resultados de diagnóstico
- `bootrepair.log`: Operaciones de reparación
- `verify.log`: Resultados de verificación
- `execution_report.txt`: Reporte detallado de la ejecución
- `test/`: Logs de pruebas y simulaciones

### Reporte de Ejecución
El reporte de ejecución incluye:
- Estado del entorno (UEFI/Legacy, WinPE, etc.)
- Estado de la ejecución (fases completadas)
- Información de backup (si se creó)
- Advertencias y errores detectados
- Recomendaciones para resolver problemas

## Contribución

1. Fork del repositorio
2. Crear rama para feature (`git checkout -b feature/AmazingFeature`)
3. Commit de cambios (`git commit -m 'Add AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abrir Pull Request

## Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.

## Seguridad

⚠️ **ADVERTENCIAS IMPORTANTES**:

1. **Ejecución Accidental**:
   - El programa requiere confirmación explícita para ejecutar cambios reales
   - Use `-SimulationMode` para pruebas seguras
   - Verifique el entorno antes de ejecutar

2. **Entorno de Pruebas**:
   - Se recomienda probar en máquinas virtuales o entornos controlados
   - Use `test-repair.ps1` para pruebas automatizadas
   - Revise los logs de prueba antes de ejecutar en producción

3. **Backup**:
   - Use `-BackupBeforeExecution` para crear backup automático
   - El backup incluye archivos críticos del sistema
   - Se restaura automáticamente en caso de error
   - Verifique tener puntos de restauración adicionales

4. **Modo Producción**:
   - Solo ejecute con `-ConfirmExecution` cuando esté seguro
   - Verifique todos los parámetros antes de ejecutar
   - Monitoree los logs durante la ejecución
   - Revise el reporte de ejecución al finalizar

5. **Manejo de Errores**:
   - El programa detecta y registra errores en cada fase
   - En caso de error crítico, restaura el backup automáticamente
   - Use `-Force` solo cuando sea absolutamente necesario
   - Revise los logs para identificar la causa de los errores 