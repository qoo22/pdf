@echo off
rem ToolBox ローカルサーバーを起動してブラウザで開きます
start "ToolBox Server" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
timeout /t 2 /nobreak >nul
start "" http://localhost:8765/
