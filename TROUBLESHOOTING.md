# Troubleshooting

## Script refuses to run

- Launch PowerShell **as Administrator**.
- On Windows PE, confirm execution policy allows local scripts.

## Simulation vs real repair

- Without `-ConfirmExecution`, destructive steps should not run (see script help).
- Use simulation flags documented in [docs/README.md](docs/README.md) before production hardware.

## BCD / UEFI still broken after repair

- Capture logs under `logs/` and open a [GitHub issue](https://github.com/drhiidden/windows-boot-repair/issues) with redacted details.
- Verify firmware boot order and that the correct ESP partition is targeted.

## `main.ps1` cannot load config

- Ensure `config/module-pipeline.config.json` exists (renamed from legacy `mcp.config.json`).
