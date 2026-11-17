@echo off
setlocal
set "PROJECT_DIR=%~dp0"
set "GODOT_EXE=C:\Test\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
	echo Godot 4.7.2 executable was not found:
	echo %GODOT_EXE%
	echo.
	pause
	exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%run.ps1" -Godot "%GODOT_EXE%"
if errorlevel 1 (
	echo.
	echo Game launch failed.
	pause
	exit /b 1
)
