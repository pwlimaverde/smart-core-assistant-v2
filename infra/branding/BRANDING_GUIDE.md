# Smart Core Tenant — Branding Guide

## Identidade da Marca

### Nome Oficial
**Smart Core Tenant** — Solução de atendimento inteligente e autossuficiente para empresas.

**Variações:**
- `Smart Core Tenant` — Nome completo (oficial)
- `Smart Core` — Nome curto (quando espaço limitado)
- `SCT` — Sigla (apenas em contextos técnicos)

### Tagline
> "Atendimento Inteligente. Sempre Disponível."

---

## Paleta de Cores

### Cores Primárias

| Cor | Hex | RGB | Uso |
|-----|-----|-----|-----|
| **Azul Primário** | `#0066CC` | RGB(0, 102, 204) | Logo, headers, CTAs |
| **Azul Escuro** | `#003D7A` | RGB(0, 61, 122) | Backgrounds escuros |
| **Branco** | `#FFFFFF` | RGB(255, 255, 255) | Texto, backgrounds claros |
| **Cinza Claro** | `#F5F5F5` | RGB(245, 245, 245) | Backgrounds secundários |
| **Cinza Escuro** | `#333333` | RGB(51, 51, 51) | Textos principais |

### Cores Secundárias (Accent)

| Cor | Hex | RGB | Uso |
|-----|-----|-----|-----|
| **Verde Sucesso** | `#27AE60` | RGB(39, 174, 96) | Status OK, success |
| **Laranja Aviso** | `#E67E22` | RGB(230, 126, 34) | Warnings, alerts |
| **Vermelho Erro** | `#E74C3C` | RGB(231, 76, 60) | Errors, critical |

---

## Tipografia

### Fontes Recomendadas

**Headings:**
- Font: `Segoe UI` (Windows), `SF Pro Display` (macOS/iOS), fallback `Arial`
- Weight: Bold (700)
- Size: 24px (H1), 20px (H2), 16px (H3)

**Body Text:**
- Font: `Segoe UI` (Windows), `SF Pro Text` (macOS/iOS), fallback `Helvetica`
- Weight: Regular (400)
- Size: 14px

**Monospace (Code):**
- Font: `Consolas`, `Monaco`, fallback `monospace`
- Size: 12px

---

## Logo & Ícone

### Logo Principal

```
┌─────────────────────────────────────────┐
│  📱 SMART CORE TENANT                   │
│                                         │
│   [Blue Diamond] Smart Core             │
│                  Tenant                 │
│                                         │
│  Tagline: Atendimento Inteligente       │
└─────────────────────────────────────────┘
```

**Versões:**
- Logo Horizontal (azul + branco)
- Logo Vertical (azul + branco)
- Logo Monochrome (para impressão)
- Ícone App (256x256, transparente)

**Uso:**
- Horizontal: Headers, websites, documentos
- Vertical: Aplicativos, instaladores, presentations
- Monochrome: Impressão, preto & branco, fax
- Ícone: App taskbar, desktop shortcut, file association

### App Icon (icon.ico)

**Tamanho:** 256×256 pixels (16×16, 32×32, 48×48, 64×64, 128×128, 256×256)

**Design:**
```
┌──────────────────────────┐
│  [Azul #0066CC bg]       │
│                          │
│        ⬡ ⬡              │  Blue diamond pattern
│       ⬡ ⬡               │  (Smart Core identity)
│      ⬡ ⬡                │
│     ⬡ ⬡                 │
│    ⬡ ⬡ ⬡               │
│   ⬡  "ST"  ⬡            │  "ST" em branco
│                          │
└──────────────────────────┘
```

**Cores:**
- Background: Azul #0066CC
- Text: Branco #FFFFFF
- Border: Azul Escuro #003D7A (subtle)
- Shadow: Transparente (0.2 opacity)

---

## Instalador (NSIS)

### Splash Screen / Welcome Page

```
╔════════════════════════════════════════════╗
║                                            ║
║           📱 Smart Core Tenant             ║
║                                            ║
║     Atendimento Inteligente. Sempre        ║
║            Disponível.                     ║
║                                            ║
║     [⬡⬡ Progress...]                      ║
║                                            ║
║     Versão 0.1.0                           ║
║     Preparando para instalação...          ║
║                                            ║
╚════════════════════════════════════════════╝
```

**Cores:**
- Background: Branco #FFFFFF
- Header: Azul #0066CC
- Text: Cinza Escuro #333333
- Progress: Azul #0066CC

### Installer Side Panel (96×482)

```
║ ███████████████ ║
║ █ Smart Core  █ ║
║ █             █ ║
║ █   Tenant    █ ║  Gradiente azul
║ █             █ ║  (escuro → claro)
║ █ v0.1.0      █ ║
║ █             █ ║
║ ███████████████ ║
```

**Design:**
- Gradiente: #003D7A (topo) → #0066CC (base)
- Logo em branco
- Versão em branco
- Altura: 482px, Largura: 96px

### Installer Banner (164×314)

```
┌────────────────────────────┐
│                            │
│   Smart Core Tenant        │  Logo + versão
│   v0.1.0                   │  (para welcome page)
│                            │
│   [⬡⬡⬡⬡⬡⬡⬡⬡⬡⬡]          │
│                            │
└────────────────────────────┘
```

**Dimensões:** 164×314 pixels
**Cores:** Azul #0066CC com logo branco

---

## Shortcuts & Desktop Icons

### Start Menu Shortcut

**Nome:** `Smart Core Tenant`  
**Description:** `Solução de atendimento inteligente`  
**Icon:** Usar `icon.ico`  
**Target:** `%LOCALAPPDATA%\SmartCoreTenant\smart_core_tenant.exe`

### Desktop Shortcut

**Nome:** `Smart Core Tenant`  
**Description:** `Atendimento Inteligente. Sempre Disponível.`  
**Icon:** Usar `icon.ico` (256×256)  
**Target:** `%LOCALAPPDATA%\SmartCoreTenant\smart_core_tenant.exe`

---

## Aplicação (In-App)

### Tema & Colors

**Light Mode:**
```
Background: #FFFFFF
Text Primary: #333333
Text Secondary: #666666
Accent: #0066CC
Success: #27AE60
Warning: #E67E22
Error: #E74C3C
```

**Dark Mode:**
```
Background: #1E1E1E
Text Primary: #FFFFFF
Text Secondary: #CCCCCC
Accent: #4D9FFF
Success: #4CAF50
Warning: #FF9800
Error: #F44336
```

### Logo/Branding Placement

- **Top-left corner:** Logo Smart Core + versão
- **Splash screen:** Logo completo + tagline
- **About dialog:** Logo + versão + copyright
- **Taskbar icon:** App icon 256×256

---

## Print Materials

### Color Printing (CMYK)

| Cor | CMYK | Pantone |
|-----|------|---------|
| Azul Primário | 100, 55, 0, 0 | 279 C |
| Azul Escuro | 100, 75, 25, 15 | 533 C |
| Verde Sucesso | 75, 0, 55, 0 | 347 C |

### Black & White (Grayscale)

- Azul → 50% Cinza
- Preto → Preto
- Branco → Branco

---

## Padrões de Uso

### ✅ Correto

- Logo horizontal em websites
- Logo vertical em apps
- Cores primárias para CTAs
- Tagline em marketing materials
- Icon em taskbar (256×256)

### ❌ Incorreto

- Esticar/distorcer logo
- Usar cores fora da paleta
- Logo sem espaço ao redor (min 10px)
- Texto sobre logo sem contraste
- Cores invertidas sem aprovação

---

## Assets Files

```
infra/branding/
├── logo-horizontal.svg        (vetor, uso geral)
├── logo-vertical.svg          (vetor, apps)
├── logo-monochrome.svg        (vetor, impressão)
├── icon-256.png               (PNG, 256×256)
├── icon.ico                   (ICO, multi-res, para app)
├── installer-logo.bmp         (BMP, 164×314, NSIS banner)
├── installer-side.bmp         (BMP, 96×482, NSIS side)
├── splash-screen.png          (PNG, 1024×768, welcome)
├── favicon.ico                (ICO, 16×16, websites)
└── color-palette.png          (PNG, reference)
```

---

## Guia de Uso em Código

### Flutter (Dart)

```dart
// Colors
class SCColors {
  static const Color primary = Color(0xFF0066CC);
  static const Color primaryDark = Color(0xFF003D7A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF333333);
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFE67E22);
  static const Color error = Color(0xFFE74C3C);
}

// Typography
class SCTypography {
  static const TextStyle heading1 = TextStyle(
    fontFamily: 'Segoe UI',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: SCColors.textDark,
  );
  
  static const TextStyle body = TextStyle(
    fontFamily: 'Segoe UI',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: SCColors.textDark,
  );
}
```

### CSS (Web)

```css
:root {
  --sc-primary: #0066CC;
  --sc-primary-dark: #003D7A;
  --sc-white: #FFFFFF;
  --sc-text-dark: #333333;
  --sc-success: #27AE60;
  --sc-warning: #E67E22;
  --sc-error: #E74C3C;
  
  --sc-font-heading: 'Segoe UI', 'SF Pro Display', Arial, sans-serif;
  --sc-font-body: 'Segoe UI', 'SF Pro Text', Helvetica, sans-serif;
  --sc-font-mono: 'Consolas', 'Monaco', monospace;
}

body {
  font-family: var(--sc-font-body);
  color: var(--sc-text-dark);
  background-color: var(--sc-white);
}

h1, h2, h3 {
  font-family: var(--sc-font-heading);
  font-weight: bold;
}

.btn-primary {
  background-color: var(--sc-primary);
  color: var(--sc-white);
}
```

---

## Revisão de Marca

Última atualização: **2026-10-03**  
Versão: **1.0**  
Responsável: **Smart Core Team**  
Próxima revisão: **2027-10-03**

---

## Contato

Para questões sobre branding:
- Email: branding@smartcoreassistant.com.br
- Docs: https://smartcoreassistant.com.br/branding
