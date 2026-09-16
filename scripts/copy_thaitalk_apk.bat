@echo off
setlocal

set "SOURCE=\\wsl.localhost\Ubuntu\home\jack\git\thaitalk\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
set "TARGET=%~dp0thaitalk.apk"

if not exist "%SOURCE%" (
    echo APK not found: "%SOURCE%"
    echo Build the ARM64 release APK in WSL first.
    exit /b 1
)

copy /Y /B "%SOURCE%" "%TARGET%"
if errorlevel 1 (
    echo Copy failed: "%TARGET%"
    exit /b 1
)

echo Copied ARM64 release APK to "%TARGET%"
exit /b 0
