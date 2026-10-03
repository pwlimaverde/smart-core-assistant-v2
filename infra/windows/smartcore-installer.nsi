; Smart Core Tenant Installer (NSIS)
; BuildDate: 2026-10-03
; Version: 0.1.0

!include "MUI2.nsh"
!include "x64.nsh"

; ============================================================================
; Settings
; ============================================================================

Name "Smart Core Tenant"
OutFile "SmartCoreTenant-0.1.0-Setup.exe"
InstallDir "$LOCALAPPDATA\SmartCoreTenant"
InstallDirRegKey HKCU "Software\SmartCoreTenant" "InstallDir"

; Require admin rights for HKCU (no UAC)
RequestExecutionLevel user

ShowInstDetails show
ShowUninstDetails show

; ============================================================================
; MUI Settings
; ============================================================================

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "PortugueseBR"

; ============================================================================
; Installer Sections
; ============================================================================

Section "Smart Core Tenant"
  SetOutPath "$INSTDIR"

  ; Files (will be extracted from CI/CD)
  File "smart_core_tenant.exe"
  File "smart_core_tenant.dll" ; If needed

  ; Create shortcuts
  CreateDirectory "$SMPROGRAMS\Smart Core"
  CreateShortCut "$SMPROGRAMS\Smart Core\Smart Core Tenant.lnk" "$INSTDIR\smart_core_tenant.exe"
  CreateShortCut "$SMPROGRAMS\Smart Core\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

  ; Desktop shortcut
  CreateShortCut "$DESKTOP\Smart Core Tenant.lnk" "$INSTDIR\smart_core_tenant.exe"

  ; Registry entries (for uninstall + version tracking)
  WriteRegStr HKCU "Software\SmartCoreTenant" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\SmartCoreTenant" "Version" "0.1.0"
  WriteRegStr HKCU "Software\SmartCoreTenant" "UpdateURL" "https://releases.smartcoreassistant.com.br"

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

; ============================================================================
; Uninstaller
; ============================================================================

Section "Uninstall"
  RMDir /r "$INSTDIR"
  RMDir /r "$SMPROGRAMS\Smart Core"
  Delete "$DESKTOP\Smart Core Tenant.lnk"
  DeleteRegKey HKCU "Software\SmartCoreTenant"
SectionEnd
