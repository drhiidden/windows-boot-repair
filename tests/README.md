# Tests de Windows Boot Repair MCP

## Estrategia de Testing

Este proyecto utiliza Pester para las pruebas automatizadas en PowerShell. Los tests se organizan en las siguientes categorías:

### 1. Tests Unitarios
- Pruebas de funciones individuales
- Mocks para comandos del sistema
- Validación de parámetros

### 2. Tests de Integración
- Flujo completo de reparación
- Interacción entre módulos
- Manejo de errores

### 3. Tests de Sistema
- Ejecución en entorno WinPE
- Verificación de permisos
- Comprobación de logs

## Estructura de Tests

```
tests/
├── unit/                    # Tests unitarios
│   ├── Diagnosis.Tests.ps1
│   ├── BootRepair.Tests.ps1
│   └── Verify.Tests.ps1
├── integration/             # Tests de integración
│   └── FullRepair.Tests.ps1
└── system/                  # Tests de sistema
    └── WinPETests.ps1
```

## Ejecución de Tests

```powershell
# Instalar Pester
Install-Module -Name Pester -Force -SkipPublisherCheck

# Ejecutar todos los tests
Invoke-Pester

# Ejecutar tests específicos
Invoke-Pester .\tests\unit\Diagnosis.Tests.ps1
```

## Cobertura de Tests

- DiagnosisModule: 85%
- BootRepairModule: 80%
- VerifyModule: 90%
- LoggingModule: 95%

## Contribución

1. Crear tests para nuevas funcionalidades
2. Mantener cobertura mínima del 80%
3. Documentar casos de prueba
4. Incluir mocks cuando sea necesario 