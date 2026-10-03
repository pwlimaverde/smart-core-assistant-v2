; Smart Core Tenant Installer (NSIS)
; Professional Branding Edition
; BuildDate: 2026-10-03
; Version: 0.1.0
;
; Branding Guide: infra/branding/BRANDING_GUIDE.md
; Colors: #0066CC (primary), #003D7A (dark), #FFFFFF (white)

!include "MUI2.nsh"
!include "x64.nsh"

; ============================================================================
; Settings
; ============================================================================

Name "Smart Core Tenant"
OutFile "SmartCoreTenant-0.1.0-Setup.exe"
InstallDir "$LOCALAPPDATA\SmartCoreTenant"
InstallDirRegKey HKCU "Software\SmartCoreTenant" "InstallDir"

; Require admin rights for HKCU (no UAC) — user context install
RequestExecutionLevel user

ShowInstDetails show
ShowUninstDetails show

; ============================================================================
; Branding Colors & Assets
; ============================================================================

; Colors (from branding/colors.json)
!define BRAND_COLOR_PRIMARY "0066CC"    ; Smart Core Blue
!define BRAND_COLOR_DARK "003D7A"       ; Smart Core Dark Blue
!define BRAND_COLOR_WHITE "FFFFFF"      ; White
!define BRAND_COLOR_TEXT "333333"       ; Dark Gray

; Company & Product Info
!define BRAND_NAME "Smart Core"
!define PRODUCT_NAME "Smart Core Tenant"
!define PRODUCT_VERSION "0.1.0"
!define COMPANY_NAME "Smart Core Inc."
!define COMPANY_URL "https://smartcoreassistant.com.br"
!define TAGLINE "Atendimento Inteligente. Sempre Disponível."

; Installer Images (from infra/branding/assets/)
!define MUI_WELCOMEFINISHPAGE_BITMAP "infra/branding/assets/installer-logo.bmp"        ; 164x314
!define MUI_WELCOMEFINISHPAGE_BITMAP_NOSTRETCH ""                                      ; Don't stretch
!define MUI_HEADERIMAGE ""                                                             ; Use our custom header
!define MUI_HEADERIMAGE_BITMAP "infra/branding/assets/installer-side.bmp"             ; 96x482
!define MUI_ICON "infra/branding/assets/icon.ico"                                     ; App icon
!define MUI_UNICON "infra/branding/assets/icon.ico"                                   ; Uninstaller icon

; ============================================================================
; MUI Settings with Branding
; ============================================================================

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "PortugueseBR"

; Customize MUI Strings (Portuguese)
LangString MUI_WELCOMEPAGE_TEXT ${LANG_PORTUGUESEBR} "Bem-vindo ao ${PRODUCT_NAME}!\n\n${TAGLINE}\n\nEste assistente instalará o ${PRODUCT_NAME} v${PRODUCT_VERSION} em seu computador.\n\nClique 'Próximo' para continuar."

LangString MUI_DIRECTORYPAGE_TEXT ${LANG_PORTUGUESEBR} "Selecione a pasta de instalação.\n\nA pasta padrão é recomendada."

LangString MUI_FINISHPAGE_TEXT ${LANG_PORTUGUESEBR} "Instalação concluída!\n\n${PRODUCT_NAME} está pronto para usar.\n\nClique 'Concluir' para sair do assistente."

LangString MUI_FINISHPAGE_RUN ${LANG_PORTUGUESEBR} "Executar ${PRODUCT_NAME} agora"

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
