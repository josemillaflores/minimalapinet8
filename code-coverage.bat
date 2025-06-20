@echo off
REM ========================
REM Set Tools & Paths
REM ========================
SET "dotnet=dotnet"
SET "coveragetool=coverlet"
SET "generatetool=reportgenerator"
SET "testproject=./test/Application.Tests.Unit/Application.Tests.Unit.csproj"
SET "testassembly=./test/Application.Tests.Unit/bin/Debug/net8.0/Application.Tests.Unit.dll"
SET "coveragedir=./coverage/"
SET "coveragefile=coverage.opencover.xml"

echo Download needed tool
dotnet tool install --global dotnet-reportgenerator-globaltool
dotnet tool install --global coverlet.console

REM ========================
REM Run Tests & Coverage
REM ========================
echo Running tests with coverage...

dotnet test %testproject% 

%coveragetool% %testassembly% ^
  --target "%dotnet%" ^
  --targetargs "test %testproject% --no-build" ^
  --output "%coveragedir%" ^
  --format opencover

REM ========================
REM Generate HTML Report
REM ========================
echo Generating report...
%generatetool% ^
  "-reports:%coveragedir%\%coveragefile%" ^
  "-targetdir:%coveragedir%\html" ^
  -reporttypes:Html

REM ========================
REM Open the Report
REM ========================
echo Opening report...
start "" "%coveragedir%\html\index.html"
