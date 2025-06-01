#Requires -Version 5.0
<#
.SYNOPSIS
    Script para ejecutar pruebas, generar cobertura de código y un informe HTML.
.DESCRIPTION
    Este script de PowerShell automatiza el proceso de:
    1. Instalar (o actualizar) las herramientas globales de .NET necesarias (coverlet, reportgenerator).
    2. Ejecutar pruebas unitarias para el proyecto especificado.
    3. Generar datos de cobertura de código usando coverlet.
    4. Generar un informe de cobertura en formato HTML usando reportgenerator.
    5. Abrir el informe HTML generado en el navegador por defecto.
    El script incluye verificación básica de errores después de cada paso crítico.
.NOTES
    Asegúrate de ejecutar este script desde el directorio raíz de tu repositorio
    donde las rutas relativas como './test/' y './coverage/' sean válidas.
    Las herramientas de .NET se instalan globalmente.
#>

# ========================
# Configuration
# ========================
$ErrorActionPreference = "Stop" # Detener en errores que terminan

# Helper function to check the exit code of the last command
function Check-LastExitCode {
    param (
        [string]$CommandName
    )
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$CommandName falló con código de salida $LASTEXITCODE."
        exit $LASTEXITCODE # Salir del script con el mismo código de error
    }
    Write-Host "$CommandName completado exitosamente." -ForegroundColor Green
}

# ========================
# Set Tools & Paths
# ========================
$dotnetCommand = "dotnet"
$coverageToolCommand = "coverlet" # Asume que coverlet.console está instalado globalmente y en el PATH
$reportGeneratorCommand = "reportgenerator" # Asume que dotnet-reportgenerator-globaltool está instalado globalmente y en el PATH

$testProject = "tests/Application.Tests.Unit/Application.Tests.Unit.csproj"
# Nota: La ruta al ensamblado de prueba es específica. Si la configuración de compilación (Debug/Release) o el TFM (net8.0) cambian, esta ruta necesitará actualizarse.
$testAssembly = "tests/Application.Tests.Unit/bin/Debug/net8.0/Application.Tests.Unit.dll"
$coverageDir = "coverage/" # Directorio para los archivos de cobertura
$coverageFileBaseName = "coverage.opencover.xml" # Nombre base del archivo de cobertura

Write-Host "Descargando herramientas necesarias (si aún no están instaladas)..."
try {
    dotnet tool install --global dotnet-reportgenerator-globaltool
    dotnet tool install --global coverlet.console
} catch {
    Write-Warning "Una o ambas herramientas ya podrían estar instaladas o hubo un problema durante la instalación. El script continuará."
    Write-Warning "Mensaje de error: $($_.Exception.Message)"
}

# ========================
# Run Tests & Coverage
# ========================
Write-Host "Ejecutando pruebas..."
& $dotnetCommand test $testProject
Check-LastExitCode -CommandName "`"$dotnetCommand test`""

Write-Host "Generando datos de cobertura con $coverageToolCommand..."
# coverlet crea 'coverage.opencover.xml' (u otro según el formato) dentro del directorio especificado en --output
& $coverageToolCommand $testAssembly `
    --target $dotnetCommand `
    --targetargs "test `"$testProject`" --no-build" `
    --output $coverageDir `
    --format "opencover"
Check-LastExitCode -CommandName "$coverageToolCommand"

# ========================
# Generate HTML Report
# ========================
Write-Host "Generando informe HTML..."
$fullCoverageFilePath = Join-Path -Path $coverageDir -ChildPath $coverageFileBaseName
$reportTargetDir = Join-Path -Path $coverageDir -ChildPath "html"

& $reportGeneratorCommand `
    "-reports:$fullCoverageFilePath" `
    "-targetdir:$reportTargetDir" `
    "-reporttypes:Html"
Check-LastExitCode -CommandName "$reportGeneratorCommand"

# ========================
# Open the Report
# ========================
Write-Host "Abriendo informe..."
$reportHtmlFile = Join-Path -Path $reportTargetDir -ChildPath "index.html"
Invoke-Item $reportHtmlFile

Write-Host "Script de cobertura de código finalizado." -ForegroundColor Cyan
