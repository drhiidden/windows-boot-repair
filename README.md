# Windows Boot Repair Toolkit

**Languages:** English · [Español](README.es.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![views](https://komarev.com/ghpvc/?username=drhiidden&repo=windows-boot-repair&label=views&color=0e75b6)](https://github.com/drhiidden/windows-boot-repair)

PowerShell toolkit to **diagnose and repair** the Windows boot manager (BIOS/UEFI, BCD, MBR).

> **About the name:** the repository was formerly `WindowsBootRepairMCP`. Here **MCP means a modular PowerShell module pipeline**, not an [Model Context Protocol](https://modelcontextprotocol.io/) server for IDEs.

## Overview

Built for **Windows PE**, elevated normal Windows sessions, or recovery media (e.g. Hiren's Boot CD). Includes diagnostics, repair steps, final verification, structured logging, simulation mode, and optional backups before destructive changes.

## Features

- Full boot diagnostics (disk health, SMART, system integrity)
- Boot repair: MBR, boot sector, BCD, UEFI configuration
- Post-repair verification (EFI files, BCD)
- Configurable logging and retention
- Simulation mode (no changes applied)
- Automatic backup before repair operations

## Requirements

- Windows 10/11 or Windows PE 10/11
- 2 GB RAM minimum
- ~100 MB disk space
- Administrator privileges

## Quick start

```powershell
git clone https://github.com/drhiidden/windows-boot-repair.git
cd windows-boot-repair
.\scripts\repair.ps1 -ConfirmExecution -BackupBeforeExecution
```

See [README.es.md](README.es.md) for Windows PE / Hiren's Boot CD steps in Spanish.

## Project layout

```
windows-boot-repair/
├── scripts/          # repair.ps1, tests, PSD1 config
├── modules/          # Diagnosis, BootRepair, Backup, Logging, …
├── config/           # module-pipeline.config.json
├── logs/             # runtime logs (gitignored)
├── tests/
└── docs/
```

Optional orchestrator: `main.ps1` reads `config/module-pipeline.config.json`.

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/README.md](docs/README.md) | Detailed usage |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues |
| [SECURITY.md](SECURITY.md) | Reporting vulnerabilities |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |

## License

MIT — see [LICENSE](LICENSE).

## Safety

- Use `-ConfirmExecution` only when you intend to apply changes.
- Test on a VM or spare machine first.
- Prefer `-BackupBeforeExecution` when supported.
- Read logs after any failure.
