@echo off
REM ===========================================================================
REM DeskcommCRM — Backup diário (wrapper para Agendador de Tarefas)
REM Executa como: powershell -ExecutionPolicy Bypass -File scripts\backup.ps1
REM ===========================================================================
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -File "scripts\backup.ps1" -KeepDays 7
exit /b %ERRORLEVEL%
