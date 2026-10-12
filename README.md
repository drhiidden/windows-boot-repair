# Windows Boot Repair Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![visitors](https://komarev.com/ghpvc/?username=drhiidden&repo=windows-boot-repair&color=00ff88&style=flat-square)

Herramienta **PowerShell** para diagnóstico y reparación del gestor de arranque de Windows (BIOS/UEFI, BCD, MBR).

> **Sobre el nombre:** el repo se llamaba `WindowsBootRepairMCP`. Aquí **MCP = pipeline modular de módulos PowerShell**, no un servidor [Model Context Protocol](https://modelcontextprotocol.io/) para IDEs. No expone herramientas MCP para Cursor/Claude Desktop.

## Descripción

Diseñada para entornos **Windows PE**, instalaciones normales con privilegios de administrador, o medios tipo Hiren's Boot CD. Incluye diagnóstico, reparación, verificación final, logging estructurado, modo simulación y copias de seguridad antes de cambios destructivos.

## Características

- **Diagnóstico completo**: estado de disco, SMART, integridad del sistema
- **Reparación de arranque**: MBR, sector de arranque, BCD y configuración UEFI
- **Verificación final**: integridad de archivos EFI y BCD
- **Logging**: niveles configurables y retención
- **Modo simulación**: pruebas sin aplicar cambios
- **Backup automático**: antes de operaciones de reparación
- **Informes**: resumen de ejecución en logs

## Requisitos

- Windows 10/11 o Windows PE 10/11
- Mínimo 2 GB RAM
- ~100 MB de espacio en disco
- Privilegios de administrador

## Instalación

```powershell
git clone https://github.com/drhiidden/windows-boot-repair.git
cd windows-boot-repair
```

### En Windows PE

1. Copiar el árbol a USB o disco local.
2. Ejecutar:

```powershell
.\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
```

### En Hiren's Boot CD

1. Copiar a `Tools\windows-boot-repair\`.
2. Misma invocación que en PE.

## Estructura del proyecto

```
windows-boot-repair/
├── scripts/          # Entrada repair.ps1, tests, config PSD1
├── modules/          # Diagnosis, BootRepair, Backup, Logging, …
├── config/           # module-pipeline.config.json (orden de módulos)
├── logs/             # Salida de ejecución (gitignored)
├── tests/
└── docs/
```

## Uso

Documentación ampliada: [docs/README.md](docs/README.md).

Orquestador modular (opcional): `main.ps1` lee `config/module-pipeline.config.json`.

## Licencia

MIT — ver [LICENSE](LICENSE).

## Seguridad

⚠️ **Advertencias**

- Requiere confirmación explícita (`-ConfirmExecution`) para cambios reales.
- Probar primero en VM o hardware desechable.
- Usar `-BackupBeforeExecution` siempre que sea posible.
- Revisar logs ante cualquier error.

Política de reporte: [SECURITY.md](SECURITY.md).
