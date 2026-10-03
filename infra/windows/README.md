# Smart Core Tenant — Windows Build & Installer

Construção e distribuição do instalador Windows com branding profissional.

## Arquitetura

```
Client (end user)
    ↓ Downloads Setup.exe
    ↓
GitHub Releases
    ↓ OR Releases Server
    ↓
Releases Server (Velopack feed)
    ├─ releases.win.json (feed)
    ├─ app-0.1.0-full.nupkg
    ├─ app-0.1.0-delta.nupkg (next version)
    └─ Setup.exe (redirects to latest)

Client Installation Flow:
Setup.exe
    ↓ (installs v0.1.0)
    ↓
Smart Core Tenant v0.1.0
    ├─ On startup: GET /api/releases
    ├─ If update available: download + install silently
    └─ On next restart: v0.1.1 ready
```

## Build Process (CI/CD)

### Trigger
```bash
git tag win-v0.1.0
git push origin win-v0.1.0
```

### GitHub Actions Workflow
1. **Windows Runner** (`windows-latest`)
2. **Flutter Build**
   - `flutter pub get`
   - `flutter build windows --release`
   - Output: `build/windows/x64/Release/`
3. **NSIS Installer**
   - Package Flutter binaries + shortcut
   - Output: `Setup.exe`
4. **Velopack Packaging**
   - `vpk pack ...`
   - Output: 
     - `app-0.1.0-full.nupkg`
     - `app-0.1.0-delta.nupkg` (if previous release exists)
     - `releases.win.json`
     - `Setup.exe` (replacement, for Velopack)
5. **Upload to Releases Server**
   - POST `/upload` com token
   - Server armazena: `/opt/smartcore/releases/0.1.0/*`
6. **GitHub Release**
   - Publica `Setup.exe` em GitHub Releases
   - Também disponível em releases.smartcoreassistant.com.br

## Files & Structure

```
infra/windows/
├── README.md (this file)
├── smartcore-installer.nsi      # NSIS script
├── assets/
│   ├── icon.ico                 # App icon (256x256)
│   ├── installer-logo.bmp       # Installer banner (164x314)
│   └── side-panel.bmp           # Installer side (96x482)

clients/apps/smart-core-tenant/
├── pubspec.yaml
├── lib/main.dart                # Velopack integration
├── windows/
│   ├── runner/
│   │   ├── main.cpp
│   │   └── smart_core_tenant.exe (built)
│   └── CMakeLists.txt
└── velopack.json                # Velopack config
```

## Local Testing (Windows)

### Prerequisites
```powershell
# Install Flutter
winget install Google.Flutter

# Install NSIS
winget install NSIS

# Install Velopack CLI
dotnet tool install -g Velopack.Cli
```

### Build Locally
```powershell
# Build Flutter
cd clients/apps/smart-core-tenant
flutter build windows --release

# Create installer with NSIS
makensis.exe C:\path\to\smartcore-installer.nsi

# Pack with Velopack
vpk pack `
  --packId SmartCoreTenant `
  --packVersion 0.1.0 `
  --packDir "build/windows/x64/Release" `
  --mainExe smart_core_tenant.exe `
  --channel win
```

### Test Installation
```powershell
# Run Setup.exe (no admin required)
.\Setup.exe

# App installs to:
# %LocalAppData%\SmartCoreTenant\

# Verify installation
Get-ItemProperty -Path HKCU:\Software\SmartCoreTenant
```

## Branding Assets

### App Icon (icon.ico)
- Size: 256x256
- Format: ICO (multi-resolution)
- Colors: Smart Core brand colors (teal + white)
- Location: `assets/icon.ico`

### Installer Logo (installer-logo.bmp)
- Size: 164x314 pixels
- Format: BMP (24-bit, no compression)
- Contains: App name + version
- Location: `assets/installer-logo.bmp`
- Usage: Right panel of NSIS installer

### Side Panel (side-panel.bmp)
- Size: 96x482 pixels
- Format: BMP (24-bit, no compression)
- Contains: Gradient or company branding
- Location: `assets/side-panel.bmp`
- Usage: Left panel of NSIS installer

## Velopack Integration

### Config (velopack.json)
```json
{
  "packId": "SmartCoreTenant",
  "appName": "Smart Core Tenant",
  "appVersion": "0.1.0",
  "mainExe": "smart_core_tenant.exe",
  "updateUrl": "https://releases.smartcoreassistant.com.br",
  "channel": "win"
}
```

### Client Integration (lib/main.dart)
```dart
import 'package:velopack_flutter/velopack_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Velopack
  await VelopackApp.build().run();
  
  // Continue app startup
  runApp(const MyApp());
}
```

## Troubleshooting

### Build Fails
- Check Flutter Windows prerequisites: `flutter doctor`
- Verify NSIS installed: `makensis.exe`
- Check Velopack version in workflow

### Setup.exe Not Generated
- Verify `build/windows/x64/Release/smart_core_tenant.exe` exists
- Check NSIS compilation output
- Ensure Velopack config is correct

### Updates Not Working
- Verify releases.win.json is on server
- Check client can reach `https://releases.smartcoreassistant.com.br/api/releases`
- Verify version in releases.win.json > client version
- Check app logs for Velopack errors

### Installer Requires Admin
- App should run without UAC (user context install)
- If UAC prompt appears, check:
  - Registry paths (should be HKCU, not HKLM)
  - Installation directory (%LocalAppData%, not Program Files)
  - NSIS `RequestExecutionLevel user`

## Release Checklist

- [ ] Version bumped in `pubspec.yaml`
- [ ] Velopack config updated with new version
- [ ] NSIS script references correct version
- [ ] Assets (icon, logos) created with brand colors
- [ ] Tag created: `git tag win-vX.Y.Z`
- [ ] Push to origin: `git push origin win-vX.Y.Z`
- [ ] GitHub Actions build completes
- [ ] Setup.exe available on GitHub Releases
- [ ] Setup.exe available on releases.smartcoreassistant.com.br
- [ ] Test local installation on Windows machine
- [ ] Test auto-update mechanism (upgrade to new version)
- [ ] Verify shortcuts created (Start menu + Desktop)
- [ ] Verify uninstall works cleanly

## Docs Externas

- [Flutter Windows Build](https://docs.flutter.dev/platform-integration/windows/building)
- [NSIS Documentation](https://nsis.sourceforge.io/Docs/)
- [Velopack Documentation](https://docs.velopack.io)
- [Velopack Flutter Package](https://pub.dev/packages/velopack_flutter)
