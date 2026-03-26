@echo off
echo ============================================
echo  Chameleon Browser - Build Script
echo ============================================
echo.

:: Configurar ambiente
set PATH=C:\depot_tools;%PATH%
set DEPOT_TOOLS_WIN_TOOLCHAIN=0

:: Pegar numero de cores do sistema
set MAX_CORES=%NUMBER_OF_PROCESSORS%

:: Verificar se ja foi passado por argumento
set JOBS=
if not "%~1"=="" if not "%~1"=="--full" set JOBS=%~1
if not "%~2"=="" set JOBS=%~2

:: Se nao foi passado, usar 16 por padrao
if not defined JOBS set JOBS=16
if "%JOBS%"=="" set JOBS=14

:: Validar: maximo = cores do sistema
if %JOBS% GTR %MAX_CORES% set JOBS=%MAX_CORES%

echo.
echo CPU cores: %MAX_CORES% / Usando: %JOBS% jobs
echo.

:: Só roda gn gen se passado --full ou se out/Default não existir
if "%~1"=="--full" call gn gen out/Default
if not exist "out\Default\build.ninja" call gn gen out/Default

:: Compilar (incremental - só recompila o que mudou)
echo Compilando Chrome (incremental, -j %JOBS%)...
call autoninja -C out/Default chrome -j %JOBS%
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
