@echo off
chcp 65001 >nul
title HR.Batra - Building APK
cd /d "%~dp0mobile"

echo ================================================
echo  HR.Batra APK Builder
echo ================================================
echo.
echo [1/4] Cleaning previous build...
call flutter clean

echo.
echo [2/4] Fetching dependencies...
call flutter pub get

echo.
echo [3/4] Building release APKs (universal + split-per-abi)...
echo (this takes 3-6 minutes on first run)
call flutter build apk --release --split-per-abi

echo.
echo [4/4] Copying APKs to desktop for easy access...
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    copy /Y "build\app\outputs\flutter-apk\app-release.apk" "%~dp0HR_Batra_universal.apk" >nul
)
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    copy /Y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "%~dp0HR_Batra_arm64.apk" >nul
)

echo.
echo ================================================
echo  BUILD DONE
echo ================================================
echo.
echo  APK files in this folder:
echo    - HR_Batra_universal.apk  (works everywhere, ~60 MB)
echo    - HR_Batra_arm64.apk      (modern phones only, ~20 MB)
echo.
echo  Send the arm64 one to your phone.
echo.
echo Press any key to close...
pause >nul
