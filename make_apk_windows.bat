@echo off
setlocal
if "%API_URL%"=="" (
  echo Set API_URL first, for example:
  echo set API_URL=https://YOUR-BACKEND-DOMAIN
  exit /b 1
)
flutter pub get || exit /b 1
if not exist android (
  flutter create --platforms=android .
  if errorlevel 1 exit /b 1
)
flutter build apk --release --dart-define=API_URL=%API_URL%
if errorlevel 1 exit /b 1
echo.
echo APK location: build\app\outputs\flutter-apk\app-release.apk
endlocal
