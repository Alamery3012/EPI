# One-command local build for Windows (PowerShell). Needs Flutter, Android SDK, Java 17, Python 3.
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File tool\build_local.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Run($cmd) {
  Write-Host ">> $cmd" -ForegroundColor Cyan
  Invoke-Expression $cmd
  if ($LASTEXITCODE -ne 0) { throw "Failed: $cmd" }
}

Run "flutter create --org org.yfca --project-name epi_app --platforms android ."

New-Item -ItemType Directory -Force -Path assets\fonts | Out-Null
foreach ($f in @("Amiri-Regular", "Amiri-Bold")) {
  Invoke-WebRequest -Uri "https://github.com/google/fonts/raw/main/ofl/amiri/$f.ttf" -OutFile "assets\fonts\$f.ttf"
}

Run "python tool\patch_android.py"
Run "flutter pub get"
Run "flutter analyze --no-fatal-infos --no-fatal-warnings"
Run "flutter test"
Run "flutter build apk --release"
Write-Host "`nAPK ready: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
