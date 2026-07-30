#!/usr/bin/env bash
# POSIX shell script to run `flutter create` then overlay existing custom app files.
# Usage: ./apply_overlay.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
TMP_DIR="$ROOT/app_temp"
BACKUP_DIR="$ROOT/app_backup_$(date +%Y%m%d_%H%M%S)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter CLI not found in PATH. Install Flutter and re-run this script." >&2
  exit 1
fi

rm -rf "$TMP_DIR"
flutter create "$TMP_DIR" --org com.visionmate --project-name visionmate

if [ -d "$APP_DIR" ]; then
  echo "Backing up existing app/ to $BACKUP_DIR"
  mv "$APP_DIR" "$BACKUP_DIR"
fi

mkdir -p "$APP_DIR"
# Copy generated scaffold
cp -a "$TMP_DIR/." "$APP_DIR/"

# Overlay our custom folders/files if present at repo root/app or repo root
for item in lib assets test pubspec.yaml analysis_options.yaml; do
  if [ -e "$ROOT/app/$item" ]; then
    echo "Overlaying $ROOT/app/$item -> $APP_DIR/$item"
    rm -rf "$APP_DIR/$item"
    cp -a "$ROOT/app/$item" "$APP_DIR/$item"
  elif [ -e "$ROOT/$item" ]; then
    echo "Overlaying $ROOT/$item -> $APP_DIR/$item"
    rm -rf "$APP_DIR/$item"
    cp -a "$ROOT/$item" "$APP_DIR/$item"
  fi
done

rm -rf "$TMP_DIR"

echo "Bootstrap complete. Run the following in a shell:"
echo "  cd $APP_DIR"
echo "  flutter pub get"
echo "  flutter build apk --debug"
