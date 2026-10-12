# Windows Boot Repair Toolkit

**Idiomas:** [English](README.md) · Español

[![Licencia: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![visitas](https://visitor-badge.laobi.icu/badge?page_id=drhiidden.windows-boot-repair&title=visitas&left_color=555&right_color=0e75b6)
Herramienta **PowerShell** para **diagnosticar y reparar** el gestor de arranque de Windows (BIOS/UEFI, BCD, MBR).

> **Sobre el nombre:** el repositorio se llamaba `WindowsBootRepairMCP`. Aquí **MCP = pipeline modular de módulos PowerShell**, no un servidor [Model Context Protocol](https://modelcontextprotocol.io/) para IDEs.

## Descripción

Pensada para **Windows PE**, Windows con privilegios de administrador, o medios de recuperación (p. ej. Hiren's Boot CD). Incluye diagnóstico, reparación, verificación final, logging, modo simulación y copias de seguridad opcionales.

## Características

- Diagnóstico de arranque (disco, SMART, integridad)
- Reparación: MBR, sector de arranque, BCD, UEFI
- Verificación posterior (EFI, BCD)
- Logging configurable
- Modo simulación
- Backup automático antes de cambios destructivos

## Requisitos

- Windows 10/11 o Windows PE 10/11
- 2 GB RAM mínimo
- ~100 MB de espacio en disco
- Privilegios de administrador

## Instalación

```powershell
git clone https://github.com/drhiidden/windows-boot-repair.git
cd windows-boot-repair
```

### Windows PE

1. Copia el árbol a USB o disco local.
2. Ejecuta:

```powershell
.\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
```

### Hiren's Boot CD

1. Copia a `Tools\windows-boot-repair\`.
2. Misma línea de comandos que en PE.

## Estructura

```
windows-boot-repair/
├── scripts/
├── modules/
├── config/           # module-pipeline.config.json
├── logs/
├── tests/
└── docs/
```

Orquestador opcional: `main.ps1` + `config/module-pipeline.config.json`.

## Documentación

| Doc | Contenido |
|-----|-----------|
| [docs/README.md](docs/README.md) | Uso detallado |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribuir |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Problemas frecuentes |
| [SECURITY.md](SECURITY.md) | Vulnerabilidades |

## Licencia

MIT — ver [LICENSE](LICENSE).

## Seguridad

- `-ConfirmExecution` solo cuando quieras aplicar cambios reales.
- Prueba en VM o hardware de desecho.
- Usa `-BackupBeforeExecution` cuando sea posible.
- Revisa los logs ante cualquier error.
