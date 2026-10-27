@echo off
setlocal
cd /d "%~dp0server"
set "PYEXE="
python -c "import sys" >nul 2>nul
if not errorlevel 1 set "PYEXE=python"
if not defined PYEXE if exist "D:\dsh-workspace\tools\python312\python.exe" set "PYEXE=D:\dsh-workspace\tools\python312\python.exe"
if not defined PYEXE (
    echo [x] Python not found. Run: winget install --id Python.Python.3.12 -e
    pause
    exit /b 1
)
echo Using: %PYEXE%
"%PYEXE%" server.py
echo.
echo Server stopped. Press any key to close.
pause >nul
