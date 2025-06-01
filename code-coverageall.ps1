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

# Define aquí tus proyectos de prueba y sus ensamblados correspondientes.
# Nota: Las rutas a los ensamblados de prueba son específicas. Si la configuración de compilación (Debug/Release) o el TFM (net8.0) cambian, estas rutas necesitarán actualizarse.
$testModules = @(
    @{
        ProjectFile = "tests/Application.Tests.Unit/Application.Tests.Unit.csproj"
        AssemblyFile = "tests/Application.Tests.Unit/bin/Debug/net8.0/Application.Tests.Unit.dll"
        Name = "Application Unit Tests"
    },
    @{
        ProjectFile = "tests/Infrastructure.Tests.Integration/Infrastructure.Tests.Integration.csproj" # <-- MODIFICA ESTA LÍNEA CON LA RUTA A TU OTRO PROYECTO DE PRUEBAS
        AssemblyFile = "tests/Infrastructure.Tests.Integration/bin/Debug/net8.0/Infrastructure.Tests.Integration.dll" # <-- MODIFICA ESTA LÍNEA CON LA RUTA AL ENSAMBLADO DE TU OTRO PROYECTO
        Name = "Infrastructure Tests Integration" # Nombre descriptivo para los logs
    }
    @{
        ProjectFile = "tests/Presentation.Tests.Integration/Presentation.Tests.Integration.csproj" # <-- MODIFICA ESTA LÍNEA CON LA RUTA A TU OTRO PROYECTO DE PRUEBAS
        AssemblyFile = "tests/Presentation.Tests.Integration/bin/Debug/net8.0/Presentation.Tests.Integration.dll" # <-- MODIFICA ESTA LÍNEA CON LA RUTA AL ENSAMBLADO DE TU OTRO PROYECTO
        Name = "Presentation Tests Integration" # Nombre descriptivo para los logs
    }
    @{
        ProjectFile = "tests/Presentation.Tests.Unit/Presentation.Tests.Unit.csproj" # <-- MODIFICA ESTA LÍNEA CON LA RUTA A TU OTRO PROYECTO DE PRUEBAS
        AssemblyFile = "tests/Presentation.Tests.Unit/bin/Debug/net8.0/Presentation.Tests.Unit.dll" # <-- MODIFICA ESTA LÍNEA CON LA RUTA AL ENSAMBLADO DE TU OTRO PROYECTO
        Name = "Presentation Tests Unit" # Nombre descriptivo para los logs
    }
    # Puedes añadir más módulos de prueba aquí, siguiendo el mismo formato.
)

$testProjectPaths = $testModules.ProjectFile
$testAssemblyPaths = $testModules.AssemblyFile

$coverageDir = "coverage/" # Directorio para los archivos de cobertura
# $coverageFileBaseName = "coverage.opencover.xml" # Ya no se usa directamente para un solo archivo combinado por coverlet

Write-Host "Rutas de proyectos de prueba configuradas: $($testProjectPaths -join ', ')"
Write-Host "Rutas de ensamblados de prueba configuradas: $($testAssemblyPaths -join ', ')"

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
Write-Host "Ejecutando pruebas para cada proyecto individualmente..."
foreach ($projectPathInLoop in $testProjectPaths) {
    Write-Host "Ejecutando pruebas para el proyecto: $projectPathInLoop"
    & $dotnetCommand test $projectPathInLoop
    # Check-LastExitCode llamará a 'exit' si hay un error, deteniendo el script.
    Check-LastExitCode -CommandName "`"$dotnetCommand test`" para el proyecto '$projectPathInLoop'"
}
Write-Host "Todas las pruebas individuales se completaron exitosamente." -ForegroundColor Green

Write-Host "Generando informes de cobertura individuales con $coverageToolCommand..."

New-Item -ItemType Directory -Path $coverageDir -ErrorAction SilentlyContinue | Out-Null
Write-Host "Asegurado que el directorio de cobertura existe: $coverageDir"

$individualCoverageFiles = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $testModules.Count; $i++) {
    $module = $testModules[$i]
    $projectFile = $module.ProjectFile
    $assemblyFile = $module.AssemblyFile
    # Crear un nombre de archivo único para el informe de cobertura de este módulo
    $moduleNameForFile = $module.Name -replace '[^a-zA-Z0-9_.-]', '_' # Sanitize name
    $outputCoverageFile = Join-Path -Path $coverageDir -ChildPath "coverage.$moduleNameForFile.opencover.xml"

    Write-Host "Generando datos de cobertura para el ensamblado: $assemblyFile (Proyecto: $projectFile)"
    Write-Host "Archivo de salida de cobertura: $outputCoverageFile"

    # Para coverlet, --targetargs debe ser específico para el proyecto actual
    $currentTargetArgs = "test `"$projectFile`" --no-build"

    & $coverageToolCommand $assemblyFile `
        --target $dotnetCommand `
        --targetargs $currentTargetArgs `
        --output $outputCoverageFile `
        --format "opencover"
    Check-LastExitCode -CommandName "$coverageToolCommand para el ensamblado '$assemblyFile'"
    $individualCoverageFiles.Add($outputCoverageFile)
}

# ========================
# Generate HTML Report
# ========================
Write-Host "Generando informe HTML..."
$reportsForGenerator = $individualCoverageFiles -join ';' # reportgenerator usa ';' como separador para múltiples informes
$reportTargetDir = Join-Path -Path $coverageDir -ChildPath "html"

& $reportGeneratorCommand `
    "-reports:$reportsForGenerator" `
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
