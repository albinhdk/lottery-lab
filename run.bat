@echo off
setlocal
cd /d "%~dp0"

echo [Lottery Lab] 启动后端...
if exist "%~dp0backend\target\release\lottery_lab_backend.exe" (
  start "Lottery Lab Backend" /D "%~dp0backend" "%~dp0backend\target\release\lottery_lab_backend.exe"
) else (
  start "Lottery Lab Backend" /D "%~dp0backend" cmd /c "set LOTTERY_DB=data\lottery.db && cargo run"
)

echo [Lottery Lab] 等待后端就绪...
timeout /t 4 /nobreak >nul

if exist "%~dp0frontend\build\windows\x64\runner\Release\lottery_lab_app.exe" (
  echo [Lottery Lab] 启动桌面应用...
  start "" "%~dp0frontend\build\windows\x64\runner\Release\lottery_lab_app.exe"
) else (
  echo [Lottery Lab] 未找到发布版，使用 flutter run...
  cd /d "%~dp0frontend"
  flutter run -d windows
)
