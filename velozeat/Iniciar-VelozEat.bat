@echo off
cd /d "%~dp0backend"
chcp 65001 >nul
title VelozEat - Arranque
echo ================================================
echo   VelozEat - Arranque rapido
echo ================================================
echo.

if not exist node_modules (
  echo Instalando dependencias del backend...
  call npm install
  if errorlevel 1 (
    echo.
    echo No se pudieron instalar las dependencias. Revisa que Node.js este instalado.
    pause
    exit /b 1
  )
)

echo Iniciando servidor en una ventana aparte...
start "VelozEat API" cmd /k "node server.js"
timeout /t 2 >nul

echo Abriendo VelozEat en el navegador...
start "" "http://localhost:3100"
echo.
echo Listo. La ventana "VelozEat API" debe quedar abierta.
timeout /t 3 >nul
