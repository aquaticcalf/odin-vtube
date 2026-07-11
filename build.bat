@echo off
setlocal
cd /d "%~dp0"

echo Building OdinVTube...
odin build . -out:odin-vtube.exe -o:speed
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)
echo.
echo OK - run: odin-vtube.exe
echo Working directory should be this folder so assets/configs resolve.
endlocal
