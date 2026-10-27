# Sürüm derlemesi: arayüz + iki işçi süreç + Python motoru, tek klasörde.
#   powershell -File tool/build.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host '== 1/4 işçiler derleniyor ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Force build | Out-Null
Push-Location worker
dart pub get
dart compile exe bin/idle_worker.dart -o ../build/idle_worker.exe
Pop-Location
if (-not (Test-Path build/idle_worker.exe)) { throw 'idle_worker derlenemedi' }
flutter pub get
Push-Location achievements_core
dart pub get
dart compile exe bin/achievements_worker.dart -o ../build/achievements_worker.exe
Pop-Location
if (-not (Test-Path build/achievements_worker.exe)) { throw 'achievements_worker derlenemedi' }

Write-Host '== 2/4 arayüz derleniyor ==' -ForegroundColor Cyan
flutter build windows --release

Write-Host '== 3/4 paketleniyor ==' -ForegroundColor Cyan
$out = 'build/windows/x64/runner/Release'
Copy-Item build/idle_worker.exe, build/achievements_worker.exe $out -Force
New-Item -ItemType Directory -Force "$out/engine" | Out-Null
Copy-Item engine/engine.py, engine/requirements.txt "$out/engine" -Force

Write-Host '== 4/4 bitti ==' -ForegroundColor Cyan
Write-Host "PAKET : $out" -ForegroundColor Green
Write-Host 'Çalıştır: play_hub.exe'
