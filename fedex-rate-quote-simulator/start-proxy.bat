@echo off
cd /d "%~dp0"
echo Starting FedEx CORS proxy on http://localhost:8765 ...
echo Keep this window open while using fedex-rate-quote-simulator.html
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fedex_proxy.ps1"
pause
