# Script de prueba para WindowsBootRepairMCP
# Este script ejecuta el programa en modo simulación para pruebas seguras

Write-Host "=== MODO DE PRUEBA - WindowsBootRepairMCP ===" -ForegroundColor Yellow
Write-Host "Este script ejecutará el programa en modo simulación sin realizar cambios reales en el sistema."
Write-Host "Los resultados se guardarán en la carpeta logs/test"
Write-Host ""

# Verificar si estamos en un entorno de pruebas
$isTestEnvironment = $env:COMPUTERNAME -match "TEST|LAB|DEV"
if (-not $isTestEnvironment) {
    Write-Warning "¡ADVERTENCIA! No se detectó un entorno de pruebas."
    Write-Warning "Se recomienda ejecutar este script en un entorno controlado."
    $confirmation = Read-Host "¿Desea continuar de todos modos? (S/N)"
    if ($confirmation -ne "S") {
        Write-Host "Ejecución cancelada por el usuario." -ForegroundColor Red
        exit 1
    }
}

# Ejecutar el script principal en modo simulación
try {
    & "$PSScriptRoot\repair.ps1" -SimulationMode -ConfirmExecution -Mode Full
} catch {
    Write-Error "Error durante la ejecución de pruebas: $_"
    exit 1
}

Write-Host "`n=== Pruebas completadas ===" -ForegroundColor Green
Write-Host "Revise los logs en la carpeta logs/test para ver los resultados detallados." 