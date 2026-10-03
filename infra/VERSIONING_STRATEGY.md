# Smart Core Tenant — Estratégia de Versionamento e Ambientes

## 🏗️ Arquitetura de Ambientes

### Dois Ambientes, Duas Branches Git

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION                               │
│  - Branch: main                                             │
│  - Servidor: smartcore.com.br (v2-prod stack)             │
│  - Versão: v1.0.0+ (release tags)                          │
│  - Status: Clientes reais usam (estável)                   │
│  - Download: Desativado na landing page                    │
└─────────────────────────────────────────────────────────────┘
                          ↓
                    (merging to main)
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                    DEVELOPMENT                              │
│  - Branch: dev                                              │
│  - Servidor: dev.smartcoreassistant.com.br (v2-dev stack) │
│  - Versão: v0.1.0 (beta, em desenvolvimento)              │
│  - Status: Testes internos, iteração rápida               │
│  - Download: Via Admin Dashboard apenas                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Versionamento: Channels de Atualização

### Landing Page (`https://smartcoreassistant.com.br`)

**Botão de Download:**
- ✅ Status: **DESATIVADO**
- Título: "↓ Versão em Desenvolvimento"
- Tooltip: "Versão beta em desenvolvimento. Acesso via Admin Dashboard"
- Razão: Prod ainda não está disponível (stack v2-prod não ativa)

**Quando prod abrir:**
- [ ] Ativar botão
- [ ] Link: `GET /api/releases?channel=stable` 
- [ ] Serve: Setup.exe v1.0.0+ (produção)

---

### Admin Dashboard (`https://smartcoreassistant.com.br/admin.html`)

**Abas de Versões:**

| Aba | Channel | Versão | Ambiente | Status |
|-----|---------|--------|----------|--------|
| **Todas** | (all) | Qualquer | Ambos | ✅ Ativa |
| **Estável** | `stable` | v1.0.0+ | Produção | ⏳ Futuro |
| **Beta** | `beta` | v0.x.x | Dev | ✅ Ativa |
| **Dev** | `dev` | v0.1.0-dev | Dev | ✅ Ativa |

**Acesso:**
- Só admins/devs têm acesso
- Podem testar versões beta
- Podem copiar links para feedback

---

## 🔀 Fluxo de Versionamento

### Desenvolvimento (DEV)

```
1. Dev trabalha na branch dev
2. Push → GitHub Actions: build-windows-installer.yml
3. Compila Setup.exe com tag win-v0.x.x-beta
4. Publica em servidor releases (channel=beta)
5. Admin dashboard: versão aparece em "Beta"
6. Devs testam via admin
7. Bug fixes → volta pro passo 2
```

**Tags usadas:**
- `win-v0.1.0-beta` → Setup.exe para testes

---

### Produção (PROD)

```
1. Quando dev está estável
2. Merge dev → main (pull request)
3. GitHub Actions: deploy-prod.yml
4. Tag: v1.0.0 (sem prefix "win-")
5. Compila Setup.exe de produção
6. Publica em releases com channel=stable
7. Landing page: botão ativa
8. Clientes: atualizam de forma automática (Velopack)
```

**Tags usadas:**
- `v1.0.0` → Setup.exe para produção
- `v1.0.1` → Patch produção
- `v2.0.0` → Major release

---

## 🌐 Servidor de Releases — Como Diferencia

### GET /api/releases (com query param `channel`)

```bash
# Cliente DEV/BETA checa updates
GET /api/releases?channel=beta
Response:
{
  "version": "0.1.0-beta",
  "channel": "beta",
  "url": "https://releases.../download/0.1.0-beta/Setup.exe",
  "mandatory": false,
  "releaseNotes": "Beta para testes internos"
}

# Cliente PROD checa updates
GET /api/releases?channel=stable
Response:
{
  "version": "1.0.0",
  "channel": "stable",
  "url": "https://releases.../download/1.0.0/Setup.exe",
  "mandatory": false,
  "releaseNotes": "Release estável para produção"
}
```

### Sem query param (default)

```bash
GET /api/releases
# Retorna versão ESTÁVEL (channel=stable)
# Se não existir, retorna BETA como fallback
```

---

## 📋 Landing Page — Estados

### Agora (Só Dev)

```
┌─────────────────────────────────────┐
│ Smart Core Tenant                   │
│                                     │
│ Atendimento Inteligente.            │
│ Sempre Disponível.                  │
│                                     │
│ ↓ Versão em Desenvolvimento  [❌]   │ ← DESATIVADO
│ Criar Conta              [⏳]       │ ← FUTURO
│                                     │
└─────────────────────────────────────┘
```

### Quando Prod Abrir

```
┌─────────────────────────────────────┐
│ Smart Core Tenant                   │
│                                     │
│ Atendimento Inteligente.            │
│ Sempre Disponível.                  │
│                                     │
│ ↓ Baixar v1.0.0          [✅]       │ ← ATIVADO
│ Criar Conta              [✅]       │ ← ATIVADO
│                                     │
└─────────────────────────────────────┘
```

---

## 🔐 Admin Dashboard — Restricted Access

### Quem Pode Acessar

```
✅ URL: https://smartcoreassistant.com.br/admin.html
✅ Acesso: Público (sem autenticação) — MUDAR NO FUTURO
❌ Recomendação: Adicionar auth quando prod abrir
```

### Mudanças Futuras (Quando Prod Abrir)

```javascript
// Adicionar verificação de permissão
if (!isAdminOrDeveloper()) {
  redirect('/');
  return;
}

// Ou: exigir token
const token = getAuthToken();
if (!token || !isValidAdminToken(token)) {
  show403();
  return;
}
```

---

## 🚀 Migração para Produção (Checklist)

Quando v1.0.0 estiver pronto:

- [ ] Merge pull request: dev → main
- [ ] Tag criada: `v1.0.0` (sem `win-` prefix)
- [ ] GitHub Actions compila Setup.exe
- [ ] Upload para releases com `channel=stable`
- [ ] Ativar botão de download na landing page
- [ ] Testar download da versão v1.0.0
- [ ] Clientes começam a receber updates automáticos
- [ ] Adicionar autenticação no admin dashboard
- [ ] Monitorar telemetria de updates

---

## 📊 Resumo da Separação

| Aspecto | DEV | PROD |
|---------|-----|------|
| **Branch** | dev | main |
| **Tag Format** | win-v0.x.x-beta | v1.x.x |
| **Channel** | beta | stable |
| **Landing Download** | ❌ Desativado | ✅ Ativado (futuro) |
| **Admin Access** | ✅ Público | ⚠️ Deve ser restrito |
| **Versão Exemplo** | v0.1.0-beta | v1.0.0 |
| **Status** | ✅ Ativo | ⏳ Futuro |

---

## 🔄 Fluxo Completo (Hoje)

```
┌─────────────┐
│ Dev commits │
└──────┬──────┘
       │
       ↓ Push dev
┌─────────────────────────────────┐
│ GitHub Actions: build-windows   │
│ - Compila app Windows           │
│ - Cria Setup.exe v0.1.0-beta    │
│ - Publica em releases/0.1.0-beta│
└──────┬──────────────────────────┘
       │
       ↓ Upload completo
┌──────────────────────────────────────────┐
│ Admin Dashboard                          │
│ - Aba "Todas": v0.1.0-beta aparece      │
│ - Aba "Beta": v0.1.0-beta aparece       │
│ - Admin clica "Baixar Setup.exe"        │
│ - Download: releases/.../Setup.exe      │
└──────┬───────────────────────────────────┘
       │
       ↓ Testes
   [✅ OK]
       │
       ↓ Quando pronto para prod
┌──────────────────────────────┐
│ Pull Request: dev → main      │
│ Merge & Tag: v1.0.0           │
│ Prod stack ativa              │
│ Landing page: Download ON     │
└──────────────────────────────┘
```

---

**Status Atual:** ✅ DEV ativo, ⏳ PROD planejado  
**Data:** 2026-10-03  
**Próxima Ação:** Quando prod estiver pronto, ativar landing page
