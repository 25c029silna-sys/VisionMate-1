# Bootstrap Flutter app using `flutter create` and overlay custom files
# Usage (PowerShell):
#   .\bootstrap_flutter_app.ps1

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)/.."
Set-Location $root

$appDir = Join-Path $root 'app'
$tmpDir = Join-Path $root 'app_temp'
$backupDir = Join-Path $root "app_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

function Check-Flutter {
    try {
        flutter --version > $null 2>&1
        return $true
    } catch {
        Write-Error 'Flutter CLI not found in PATH. Install Flutter and re-run this script.'
        return $false
    }
}

if (-not (Check-Flutter)) { exit 1 }

if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }

Write-Host 'Creating fresh Flutter app into temporary folder...'
flutter create $tmpDir --org com.visionmate --project-name visionmate

if (-not (Test-Path $tmpDir)) {
    Write-Error 'flutter create failed or temporary folder missing.'
    exit 1
}

# Back up existing app directory if present
if (Test-Path $appDir) {
    Write-Host "Backing up existing app/ to $backupDir"
    Move-Item $appDir $backupDir
}

# Prepare overlay: copy our custom lib, assets, test, pubspec.yaml, analysis_options.yaml
Write-Host 'Overlaying custom files into generated app...'
New-Item -ItemType Directory -Path $appDir | Out-Null

# Copy generated native folders into new app
Copy-Item -Recurse -Force -Path (Join-Path $tmpDir '*') -Destination $appDir

# Overwrite with our custom modules (lib, assets, test, pubspec, analysis)
$itemsToOverlay = @('lib', 'assets', 'test', 'pubspec.yaml', 'analysis_options.yaml')
foreach ($item in $itemsToOverlay) {
    $src = Join-Path $root 'app' $item
    $altSrc = Join-Path $root $item
    if (Test-Path $src) {
        Write-Host "Overlaying $src -> $appDir\$item"
        Copy-Item -Recurse -Force -Path $src -Destination (Join-Path $appDir $item)
    } elseif (Test-Path $altSrc) {
        Write-Host "Overlaying $altSrc -> $appDir\$item"
        Copy-Item -Recurse -Force -Path $altSrc -Destination (Join-Path $appDir $item)
    }
}

# Clean up temp
Remove-Item -Recurse -Force $tmpDir

Write-Host 'Bootstrap complete. Next steps:'
Write-Host "  cd $appDir"
Write-Host '  flutter pub get'
Write-Host '  flutter build apk --debug'
