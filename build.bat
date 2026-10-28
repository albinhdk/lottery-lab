@echo off
setlocal
cd /d "%~dp0"

echo [1/3] 构建 Rust 后端...
cd /d "%~dp0backend"
cargo build --release
if errorlevel 1 exit /b 1

echo [2/3] 构建 Flutter Windows 应用...
cd /d "%~dp0frontend"
flutter build windows --release
if errorlevel 1 exit /b 1

echo [3/3] 构建 Flutter Web 版本...
flutter build web --release
if errorlevel 1 exit /b 1

echo.
echo 构建完成：
echo   后端: backend\target\release\lottery_lab_backend.exe
echo   桌面: frontend\build\windows\x64\runner\Release\lottery_lab_app.exe
echo   Web : frontend\build\web
