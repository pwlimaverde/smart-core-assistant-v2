# Smart Core Tenant — Guia de Assets para Branding

## Paleta de Cores Oficial

```
Primária:     #0066CC (Azul Smart Core)
Primária Esc: #003D7A (Azul Escuro)
Texto:        #333333 (Cinza Escuro)
Fundo:        #F5F5F5 (Cinza Claro)
Sucesso:      #27AE60 (Verde)
Aviso:        #E67E22 (Laranja)
Erro:         #E74C3C (Vermelho)
```

## Arquivos Necessários

### 1. icon.ico (256×256)
**Uso:** App icon no taskbar, desktop shortcut, file association
**Tamanho:** Multi-resolução (16×16, 32×32, 48×48, 64×64, 128×128, 256×256)
**Design:** 
- Background: Azul #0066CC
- Símbolo: Diamond/losango pattern (identidade Smart Core)
- Transparência: Suportada
- Localização:** `infra/branding/assets/icon.ico`

**Como criar:**
1. Abrir Figma/Adobe XD
2. Canvas 256×256 px
3. Background azul #0066CC
4. Desenhar losangos brancos (#FFFFFF) no centro
5. Exportar como .ico com multi-resolução

### 2. installer-logo.bmp (164×314)
**Uso:** Banner lateral do instalador NSIS (Welcome page)
**Tamanho:** Exatamente 164×314 pixels
**Formato:** 24-bit ou 32-bit BMP (sem compressão)
**Design:**
- Background: Gradiente #0066CC → #003D7A (vertical)
- Logo: Smart Core vertical + "Tenant" abaixo
- Tagline: "Atendimento Inteligente. Sempre Disponível."
- Cores: Branco (#FFFFFF) para texto e logo
- Localização:** `infra/branding/assets/installer-logo.bmp`

**Como criar:**
1. Figma/Photoshop: Canvas 164×314 px
2. Fundo: Gradiente azul (claro → escuro)
3. Logo: Importar logo_vertical.svg e ajustar para caber
4. Exportar como BMP 24-bit

### 3. installer-side.bmp (96×482)
**Uso:** Painel lateral do instalador NSIS (lado esquerdo)
**Tamanho:** Exatamente 96×482 pixels
**Formato:** 24-bit BMP (sem compressão)
**Design:**
- Background: Cor sólida #003D7A (azul escuro)
- Decoração: 3-4 losangos (#0066CC) distribuídos verticalmente
- Elementos gráficos: Linhas/padrão sutil
- Localização:** `infra/branding/assets/installer-side.bmp`

**Como criar:**
1. Figma/Photoshop: Canvas 96×482 px
2. Fundo sólido: #003D7A
3. Padrão: Losangos azul claro (#0066CC) com transparência
4. Exportar como BMP 24-bit

## Paleta de Cores para Referência

| Nome | Hex | RGB | Uso |
|------|-----|-----|-----|
| Azul Primário | #0066CC | 0, 102, 204 | Logo, botões, headers |
| Azul Escuro | #003D7A | 0, 61, 122 | Fundos, navbar |
| Branco | #FFFFFF | 255, 255, 255 | Texto em azul |
| Cinza Escuro | #333333 | 51, 51, 51 | Texto principal |
| Cinza Claro | #F5F5F5 | 245, 245, 245 | Fundos secundários |
| Verde | #27AE60 | 39, 174, 96 | Sucesso |
| Laranja | #E67E22 | 230, 126, 34 | Aviso |
| Vermelho | #E74C3C | 231, 76, 60 | Erro |

## Fonte Recomendada

- **Instalador:** Segoe UI (Windows nativa) ou Arial
- **Tamanho:** 11-12px para texto, 16-18px para títulos
- **Peso:** Regular (400) para body, Bold (700) para títulos

## Checklist de Implementação

- [ ] icon.ico criado e testado
- [ ] installer-logo.bmp criado (164×314)
- [ ] installer-side.bmp criado (96×482)
- [ ] Cores validadas em todo o instalador
- [ ] NSIS compilado e testado
- [ ] Setup.exe visual conferido
- [ ] Atalhos criados com ícone correto
- [ ] Branding visual coerente com site/app

## Referências Externas

- **Figma:** Criar projeto "Smart Core Tenant Branding"
- **Assets Inspiration:**
  - Site: https://smartcoreassistant.com.br (cores, layout)
  - App: Smart Core Tenant (Figma/Flutter design)
  - Paleta: `infra/branding/colors.json`

## Próximas Etapas

1. Designer: Criar assets em Figma/Photoshop
2. Dev: Adicionar .bmp e .ico a `infra/branding/assets/`
3. CI/CD: Atualizar `.github/workflows/build-windows-installer.yml` para copiar assets
4. Teste: Compilar NSIS e validar visual do Setup.exe
5. Release: Tag `win-v0.1.0` → CI/CD completo

---

**Data:** 2026-10-03  
**Status:** Aguardando criação de assets  
**Prioridade:** Alta (bloqueador para Setup.exe visual profissional)
