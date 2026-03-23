@echo off
echo ============================================
echo  Chameleon Browser - Build Script
echo ============================================
echo.

:: Configurar ambiente
set PATH=C:\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0

:: Compilar
echo [3/3] Compilando Chrome (isso vai demorar)...
call autoninja -C out/Default chrome
if %errorlevel% neq 0 (
    echo.
    echo ERRO: Build falhou!
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Build concluido com sucesso!
echo  Executavel: out\Default\chrome.exe
echo ============================================
pause
