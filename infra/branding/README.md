# Smart Core Tenant — Branding Central

Identidade visual oficial do Smart Core Tenant.

## 📁 Estrutura

```
infra/branding/
├── BRANDING_GUIDE.md     ← Guia completo de branding
├── ASSETS_GUIDE.md       ← Instruções para criar assets (.ico, .bmp)
├── colors.json           ← Paleta de cores em JSON
├── logo-horizontal.svg   ← Logo horizontal (vetor)
├── logo-vertical.svg     ← Logo vertical (vetor)
└── assets/
    ├── icon.ico          ← Ícone do app (256×256, multi-res)
    ├── installer-logo.bmp    ← Banner lateral NSIS (164×314)
    └── installer-side.bmp    ← Painel lateral NSIS (96×482)
```

## 🎨 Cores Oficiais

**Primária:** `#0066CC` (Azul Smart Core)
**Escura:** `#003D7A`
**Branco:** `#FFFFFF`
**Texto:** `#333333`

Ver `colors.json` para paleta completa.

## 📦 Como Usar

### Para Desenvolvedores
1. Abrir `BRANDING_GUIDE.md` para referência de cores/tipografia
2. Usar `colors.json` em builds/configs
3. Consultar logo-{horizontal,vertical}.svg para branding

### Para Designers
1. Ler `ASSETS_GUIDE.md` completamente
2. Criar assets em Figma/Photoshop seguindo especificações
3. Salvar em `assets/` com nomes exatos

### Para CI/CD
1. Setup.exe: Referenciar assets do `assets/`
2. App Flutter: Usar tema `smart_core_theme.dart`
3. Website: Usar `colors.json` ou valores hexadecimais

## ⚠️ Requerimentos Imediatos

**BLOQUEANTE:**
- [ ] icon.ico criado e validado
- [ ] installer-logo.bmp (164×314 BMP)
- [ ] installer-side.bmp (96×482 BMP)

Sem estes 3 arquivos, o Setup.exe fica com branding genérico.

## 📝 Historicco

| Data | Mudança |
|------|---------|
| 2026-10-03 | Estrutura criada, assets pendentes |
| TBD | Assets criados |
| TBD | NSIS com branding completo |
| TBD | v0.1.0 com identidade visual 100% |

---

**Status:** ⚠️ Aguardando assets de branding  
**Próxima ação:** Designer criar icon.ico + banners BMP conforme ASSETS_GUIDE.md
