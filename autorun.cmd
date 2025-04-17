@echo off
cd /d %~dp0
powershell.exe -ExecutionPolicy Bypass -File "Tools\WindowsBootRepairMCP\scripts\repair.ps1"