@echo off
echo ============================================
echo  Chameleon Browser - Test Run
echo ============================================
echo.
echo Iniciando com perfil isolado...
echo Perfil: E:\CHAMALEON\chameleon_profile
echo.
start "" "E:\CHAMALEON\out\Default\chrome.exe" --user-data-dir="E:\CHAMALEON\chameleon_profile"
