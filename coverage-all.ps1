 $ErrorActionPreference = "Stop" # Detener en errores que terminan, excepto donde se maneje explícitamente
 $BuildConfiguration = "Debug" # Cambia a "Release" si es necesario
 $SearchPathForTestProjects = $PSScriptRoot # Directorio base para buscar proyectos de prueba (directorio del script)
 
 # Helper function to check the exit code of the last command for critical steps
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
 
 $coverageDir = Join-Path -Path $PSScriptRoot -ChildPath "coverage" # Directorio para todos los archivos de salida
 $testResultsDir = Join-Path -Path $coverageDir -ChildPath "test_results" # Directorio para los archivos .trx
 $coverageReportDir = Join-Path -Path $coverageDir -ChildPath "html" # Directorio para el informe de cobertura HTML
 $failureReportHtmlFile = Join-Path -Path $coverageDir -ChildPath "test_failures_report.html"
 
 # ========================
 # Discover Test Projects
 # ========================
 Write-Host "Descubriendo proyectos de prueba en '$SearchPathForTestProjects' y subdirectorios..." -ForegroundColor Yellow
 $discoveredTestProjectFiles = Get-ChildItem -Path $SearchPathForTestProjects -Recurse -Filter *.csproj
 $initialTestModules = [System.Collections.Generic.List[hashtable]]::new()
 
 foreach ($projectItem in $discoveredTestProjectFiles) {
     try {
         [xml]$csprojContent = Get-Content -Path $projectItem.FullName -Raw
         $isTestProjectNode = $csprojContent.SelectSingleNode("//IsTestProject")
         if ($isTestProjectNode -and ($isTestProjectNode.InnerText -eq 'true')) {
             $moduleName = $projectItem.BaseName # ej. Application.Tests.Unit
             Write-Host "Proyecto de prueba encontrado: '$($projectItem.FullName)' (Nombre: $moduleName)" -ForegroundColor Cyan
             $initialTestModules.Add(@{
                 ProjectFile = $projectItem.FullName
                 Name        = $moduleName
             })
         }
     }
     catch {
         Write-Warning "Error al procesar el archivo '$($projectItem.FullName)': $($_.Exception.Message). Omitiendo."
     }
 }
 
 if ($initialTestModules.Count -eq 0) {
     Write-Error "No se encontraron proyectos de prueba (<IsTestProject>true</IsTestProject>) en '$SearchPathForTestProjects'. Saliendo."
     exit 1
 }
 Write-Host "Se encontraron $($initialTestModules.Count) proyectos de prueba."
 
 # ========================
 # Preprocess and Validate Test Modules
 # ========================
 Write-Host "`nProcesando y validando módulos de prueba descubiertos (Configuración: $BuildConfiguration)..." -ForegroundColor Yellow
 $processedTestModules = [System.Collections.Generic.List[hashtable]]::new()
 foreach ($moduleDef in $initialTestModules) {
     $projectFile = $moduleDef.ProjectFile
     $moduleName = $moduleDef.Name
 
     # ProjectFile ya está validado por Get-ChildItem, pero una comprobación extra no hace daño
     if (-not (Test-Path $projectFile)) {
         Write-Warning "El archivo de proyecto '$projectFile' para el módulo '$moduleName' no existe (esto no debería ocurrir). Omitiendo este módulo."
         continue
     }
 
     $targetFramework = $null
     try {
         [xml]$xml = Get-Content -Path $projectFile -Raw
         $targetFramework = $xml.Project.PropertyGroup.TargetFramework | Select-Object -First 1
         if ([string]::IsNullOrWhiteSpace($targetFramework)) {
             $targetFrameworks = $xml.Project.PropertyGroup.TargetFrameworks | Select-Object -First 1
             if (-not [string]::IsNullOrWhiteSpace($targetFrameworks)) {
                 $targetFramework = ($targetFrameworks -split ';')[0].Trim()
             }
         }
     } catch {
         Write-Warning "Error al leer TargetFramework de '$projectFile' para el módulo '$moduleName': $($_.Exception.Message). Omitiendo este módulo."
         continue
     }
 
     if ([string]::IsNullOrWhiteSpace($targetFramework)) {
         Write-Warning "No se pudo determinar TargetFramework para '$projectFile' (módulo '$moduleName'). Omitiendo este módulo."
         continue
     }
 
     $projectDirectory = (Get-Item $projectFile).DirectoryName
     $assemblyFile = Join-Path -Path $projectDirectory -ChildPath "bin\$BuildConfiguration\$targetFramework\$($moduleName).dll"
 
     $processedTestModules.Add(@{
         ProjectFile     = $projectFile
         AssemblyFile    = $assemblyFile
         Name            = $moduleName # Ya es el BaseName
         TargetFramework = $targetFramework
         ProjectBaseName = $moduleName # Para consistencia, ya que Name es el BaseName
     })
 }
 $testModules = $processedTestModules # Usar la lista procesada de ahora en adelante
 if ($testModules.Count -eq 0) {
     Write-Error "No se procesaron módulos de prueba válidos después de la validación. Saliendo."
     exit 1
 }
 Write-Host "Módulos de prueba procesados exitosamente."
 
 Write-Host "`nInstalando/Actualizando herramientas globales de .NET (coverlet, reportgenerator)..."
 try {
     & $dotnetCommand tool install --global dotnet-reportgenerator-globaltool --verbosity quiet
     & $dotnetCommand tool install --global coverlet.console --verbosity quiet
 } catch {
     Write-Warning "Una o ambas herramientas ya podrían estar instaladas o hubo un problema durante la instalación. El script continuará."
     Write-Warning "Mensaje de error: $($_.Exception.Message)"
 }
 
 # ========================
 # Prepare Output Directories
 # ========================
 if (-not (Test-Path $coverageDir)) { New-Item -ItemType Directory -Path $coverageDir -Force | Out-Null }
 if (-not (Test-Path $testResultsDir)) { New-Item -ItemType Directory -Path $testResultsDir -Force | Out-Null }
 if (-not (Test-Path $coverageReportDir)) { New-Item -ItemType Directory -Path $coverageReportDir -Force | Out-Null }
 Write-Host "Directorios de salida asegurados: $coverageDir, $testResultsDir, $coverageReportDir"
 
 # ========================
 # Run Tests & Collect TRX Results
 # ========================
 $failedTestProjects = [System.Collections.Generic.List[hashtable]]::new()
 
 Write-Host "`nEjecutando pruebas para cada proyecto y recolectando resultados TRX..." -ForegroundColor Yellow
 foreach ($module in $testModules) {
     $projectPath = $module.ProjectFile
     $projectName = $module.Name
     $trxLogFile = Join-Path -Path $testResultsDir -ChildPath "$($module.ProjectBaseName).trx"
     
     Write-Host "`n--- Ejecutando pruebas para: $projectName ($projectPath) ---"
     Write-Host "Archivo de resultados TRX se guardará en: $trxLogFile"
     
     & $dotnetCommand test $projectPath --configuration $BuildConfiguration --logger "trx;LogFileName=`"$trxLogFile`"" --nologo
     
     if ($LASTEXITCODE -ne 0) {
         Write-Warning "El proyecto '$projectName' tuvo fallos en las pruebas (código de salida: $LASTEXITCODE)."
         $failedTestProjects.Add(@{Name = $projectName; ProjectPath = $projectPath; TrxFile = $trxLogFile })
     } else {
         Write-Host "Pruebas para '$projectName' completadas exitosamente." -ForegroundColor Green
     }
 }
 
 # ========================
 # Generate Code Coverage
 # ========================
 Write-Host "`nGenerando informes de cobertura individuales con $coverageToolCommand..." -ForegroundColor Yellow
 $individualCoverageFiles = [System.Collections.Generic.List[string]]::new()
 
 foreach ($module in $testModules) {
     $projectFile = $module.ProjectFile
     $assemblyFile = $module.AssemblyFile
     $moduleNameForFile = $module.Name -replace '[^a-zA-Z0-9_.-]', '_' # Sanitize name for filename
     $outputCoverageFile = Join-Path -Path $coverageDir -ChildPath "coverage.$moduleNameForFile.opencover.xml"
 
     Write-Host "Generando datos de cobertura para: $($module.Name) (Ensamblado: $assemblyFile)"
 
     if (-not (Test-Path $assemblyFile)) {
         Write-Warning "El ensamblado de prueba '$assemblyFile' para '$($module.Name)' no se encontró."
         Write-Host "Intentando compilar el proyecto '$projectFile' con Configuración '$BuildConfiguration' y TargetFramework '$($module.TargetFramework)'..."
         & $dotnetCommand build $projectFile -c $BuildConfiguration -f $module.TargetFramework --nologo
         if ($LASTEXITCODE -ne 0) {
             Write-Error "Falló la compilación de '$projectFile'. Omitiendo la generación de cobertura para este módulo."
             continue 
         }
         if (-not (Test-Path $assemblyFile)) {
             Write-Error "El ensamblado de prueba '$assemblyFile' aún no existe después de la compilación. Omitiendo la generación de cobertura para este módulo."
             continue 
         }
         Write-Host "Proyecto '$projectFile' compilado exitosamente." -ForegroundColor Green
     }
     
     Write-Host "Archivo de salida de cobertura: $outputCoverageFile"
     $currentTargetArgs = "test `"$projectFile`" --configuration $BuildConfiguration --no-build" 
 
     & $coverageToolCommand $assemblyFile `
         --target $dotnetCommand `
         --targetargs $currentTargetArgs `
         --output $outputCoverageFile `
         --format "opencover" `
         --exclude-by-file "**/Migrations/*.cs" 
     Check-LastExitCode -CommandName "$coverageToolCommand para el ensamblado '$assemblyFile'"
     $individualCoverageFiles.Add($outputCoverageFile)
 }
 
 if ($individualCoverageFiles.Count -eq 0) {
     Write-Error "No se generaron archivos de cobertura. No se puede crear el informe HTML. Saliendo."
     exit 1
 }
 
 # ========================
 # Generate Consolidated HTML Coverage Report
 # ========================
 Write-Host "`nGenerando informe HTML de cobertura consolidado..." -ForegroundColor Yellow
 $reportsForGenerator = $individualCoverageFiles -join ';'
 & $reportGeneratorCommand `
     "-reports:$reportsForGenerator" `
     "-targetdir:$coverageReportDir" `
     "-reporttypes:Html"
 Check-LastExitCode -CommandName "$reportGeneratorCommand"
 
 # ========================
 # Generate Test Failures HTML Report (if any)
 # ========================
 if ($failedTestProjects.Count -gt 0) {
     Write-Warning "`nSe detectaron fallos en las pruebas. Generando informe de fallos..."
     # Asegúrate de que la siguiente línea "@" que termina este bloque HTML esté al inicio de su línea, sin espacios antes.
     # El error indica que en tu archivo, la línea 228 (el terminador "@) tiene un espacio en el carácter 2.
     $htmlContent = @"
 <!DOCTYPE html><html lang='es'><head><meta charset='UTF-8'><title>Informe de Fallos en Pruebas</title>
 <style>body{font-family:Arial,sans-serif;margin:20px;background-color:#fdf6f6;color:#333}h1{color:#d9534f;border-bottom:2px solid #d9534f;padding-bottom:10px}
 .container{background-color:#fff;padding:20px;border-radius:8px;box-shadow:0 0 15px rgba(0,0,0,0.1);border:1px solid #d9534f}
 .project{margin-bottom:15px;padding:15px;border:1px solid #ddd;border-radius:4px;background-color:#f9f9f9}
 .project.failed{border-left:5px solid #d9534f;background-color:#fff0f0}
 .project-name{font-weight:bold;color:#c9302c;font-size:1.2em}
 a{color:#0275d8;text-decoration:none}a:hover{text-decoration:underline}
 .coverage-link{display:block;margin-top:20px;padding:10px;background-color:#5cb85c;color:white;text-align:center;border-radius:4px}
 </style></head><body><div class='container'><h1>Informe de Fallos en Pruebas</h1>
 <p>Los siguientes proyectos tuvieron pruebas que fallaron durante la ejecución:</p>
"@
     foreach ($failedProject in $failedTestProjects) {
         $relativeTrxPath = "test_results/$($failedProject.TrxFile | Split-Path -Leaf)" 
         $htmlContent += "<div class='project failed'><span class='project-name'>$($failedProject.Name)</span><br/>"
         $htmlContent += "Ruta del Proyecto: $($failedProject.ProjectPath)<br/>"
         $htmlContent += "Resultados Detallados (TRX): <a href='$relativeTrxPath' target='_blank'>$($failedProject.TrxFile | Split-Path -Leaf)</a></div>"
     }
     $htmlContent += "<a href='html/index.html' target='_blank' class='coverage-link'>Ver Informe de Cobertura de Código Completo</a>"
     $htmlContent += "</div></body></html>"
     Set-Content -Path $failureReportHtmlFile -Value $htmlContent -Encoding UTF8
     Write-Host "Informe de fallos generado en: $failureReportHtmlFile" -ForegroundColor Yellow
 }
 
 # ========================
 # Open Reports
 # ========================
 Write-Host "`nAbriendo informe(s)..." -ForegroundColor Cyan
 $mainCoverageReportHtmlFile = Join-Path -Path $coverageReportDir -ChildPath "index.html"
 
 if (Test-Path $failureReportHtmlFile) {
     Invoke-Item $failureReportHtmlFile
     Write-Host "Informe de fallos abierto."
 }
 
 if (Test-Path $mainCoverageReportHtmlFile) {
     Invoke-Item $mainCoverageReportHtmlFile
     Write-Host "Informe de cobertura principal abierto."
 } else {
     Write-Warning "No se encontró el informe de cobertura principal en: $mainCoverageReportHtmlFile"
 }
 
 Write-Host "`nScript de ejecución de pruebas y cobertura finalizado." -ForegroundColor Cyan
 
 if ($failedTestProjects.Count -gt 0) {
     Write-Warning "ATENCION: Hubo fallos en las pruebas. Revisa el informe de fallos."
     # Considera salir con un código de error para CI/CD
     # exit 1
 }
