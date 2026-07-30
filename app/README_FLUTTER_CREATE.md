# Using `flutter create` to regenerate the app scaffold

This repository includes a prepared `app/` tree with feature code, assets, and tests. If you later install Flutter and want to generate a full official Flutter scaffold and merge our custom code into it, use the scripts in `scripts/`.

PowerShell (Windows):

```powershell
cd <repo_root>
./scripts/bootstrap_flutter_app.ps1
```

POSIX (Linux/macOS):

```bash
cd <repo_root>
./scripts/apply_overlay.sh
```

What the scripts do:
- Run `flutter create` to generate a fresh Flutter project into a temporary folder.
- Back up any existing `app/` to `app_backup_<timestamp>/`.
- Copy the generated native Android/iOS and Gradle files into `app/`.
- Overlay this repo's `lib/`, `assets/`, `test/`, `pubspec.yaml`, and `analysis_options.yaml` into the generated project so your custom feature code and assets remain intact.

After the script completes, run:

```bash
cd app
flutter pub get
flutter build apk --debug
```

Notes & tips:
- The script expects the repo layout created by this scaffold (our `app/` folder contains the feature code). If you moved files, adjust the script paths accordingly.
- The overlay preserves generated native files (Gradle, AndroidManifest, iOS Runner) while replacing Flutter Dart code and assets with this repo's contents.
- Review the generated `pubspec.yaml` after overlay; the script attempts to copy your `pubspec.yaml` over the generated one. If dependency conflicts occur, resolve versions manually and run `flutter pub get`.
