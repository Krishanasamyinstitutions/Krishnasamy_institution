# EduDesk Installer

This folder contains the Inno Setup script that packages the Flutter Windows
Release build into a single-file Windows installer (`EduDesk-Setup-X.Y.Z.exe`).

## One-time setup

1. Download **Inno Setup 6** (free): https://jrsoftware.org/isdl.php
2. Install the "unicode" edition (default).
3. Confirm `iscc.exe` is available — usually at
   `C:\Program Files (x86)\Inno Setup 6\iscc.exe`.

## Build the installer

From this folder, in a terminal:

```bash
# 1. Build the Flutter release first (only needed when the app code changes)
cd ..
flutter build windows --release

# 2. Compile the installer
cd installer
"C:\Program Files (x86)\Inno Setup 6\iscc.exe" EduDesk.iss
```

Or just double-click `EduDesk.iss` to open it in the Inno Setup IDE, then hit
**Build → Compile** (F9).

The output goes to `installer\dist\EduDesk-Setup-1.0.0.exe`.

## What the installer does

- Installs to `C:\Program Files\EduDesk` (admin-elevated)
- Creates a Start Menu entry
- Optionally creates a Desktop shortcut (user ticks a checkbox)
- Offers to launch the app after installation
- Registers a clean uninstaller under *Settings → Apps*

## Updating the version

Edit the top of `EduDesk.iss`:

```
#define MyAppVersion    "1.0.1"
```

Then rebuild and recompile.
