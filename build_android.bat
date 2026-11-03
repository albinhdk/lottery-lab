@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo [1/3] 刷新 APK 种子数据库...
python tools\refresh_seed_db.py
if errorlevel 1 (
  echo 提示：后端数据库不存在时跳过种子刷新，App 首次启动会联网同步。
)

echo [2/3] 交叉编译 Android 内置后端...
python tools\build_android_backend.py
if errorlevel 1 exit /b 1

echo [3/3] 构建 APK...
cd /d "%~dp0frontend"
call flutter build apk --release
if errorlevel 1 exit /b 1

if not exist "%~dp0dist" mkdir "%~dp0dist"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%~dp0dist\lottery-lab-android.apk" >nul
if errorlevel 1 exit /b 1

echo.
echo 构建完成：
echo   APK: dist\lottery-lab-android.apk
echo   内置后端: frontend\android\app\src\main\jniLibs\
