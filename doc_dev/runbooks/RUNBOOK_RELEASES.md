# Runbook — Smart Core Releases Server

> Procedimentos operacionais para publicar, reverter e revogar versões do instalador Windows.

## Pré-requisitos

- Acesso SSH ao `srv1321059` (Hostinger)
- Token de upload em `RELEASES_UPLOAD_TOKEN` (GitHub Secrets)
- Segredo de ticket em `RELEASES_DOWNLOAD_SECRET` (protegido em `.env`)
- CLI: `docker`, `gh`, `git`

---

## 📦 Publicar uma versão beta

### 1. Trigger via git tag

```bash
# No seu fork
git tag win-v0.1.0-beta.1
git push origin win-v0.1.0-beta.1
```

**O que acontece:**
- `.github/workflows/build-windows-installer.yml` dispara
- Compila Flutter + Velopack com `--channel beta`
- Upload para `releases.smartcoreassistant.com.br/upload`
- Publica GitHub Release (prerelease=true)
- Feed `releases.beta.json` é atualizado no servidor

### 2. Verificar upload

```bash
curl -s https://releases.smartcoreassistant.com.br/api/releases?channel=beta \
  | jq '.Assets[] | select(.Version == "0.1.0-beta.1")'
```

Esperar ~1-2 min (CI + upload). O app cliente checa a cada 1h.

---

## ⏮️ Reverter para versão anterior

### 1. Identificar versão atual

```bash
curl -s https://releases.smartcoreassistant.com.br/api/releases?channel=beta | jq '.Version'
```

### 2. Restaurar feed anterior

```bash
ssh root@srv1321059 'cd /opt/smartcore/releases && \
  git show HEAD~1:releases.beta.json > releases.beta.json && \
  ls -lh releases.beta.json'
```

**Se não houver git:**
```bash
# Backup manual antes de updates
cp releases.beta.json releases.beta.json.bak
# Restaurar:
cp releases.beta.json.bak releases.beta.json
```

### 3. Verificar feed

```bash
curl -s https://releases.smartcoreassistant.com.br/api/releases?channel=beta | jq '.Version'
```

---

## 🔑 Rotacionar segredos (RELEASES_DOWNLOAD_SECRET)

> Necessário se houver suspeita de exposição. A chave antiga e nova coexistem por 24h via `kid` (key rotation).

### 1. Gerar nova chave

```bash
NEW_SECRET=$(openssl rand -hex 32)
echo "Nova chave: $NEW_SECRET"
```

### 2. No servidor, atualizar .env

```bash
ssh root@srv1321059 'cat >> /opt/smartcore/releases/.env' << EOL
RELEASES_DOWNLOAD_SECRET_OLD=$RELEASES_DOWNLOAD_SECRET
RELEASES_DOWNLOAD_SECRET=$NEW_SECRET
EOL
```

### 3. Recriar container

```bash
ssh root@srv1321059 'cd docker/releases && docker compose --env-file .env up -d --force-recreate'
```

### 4. Remover chave antiga após 24h

```bash
ssh root@srv1321059 'sed -i "/RELEASES_DOWNLOAD_SECRET_OLD/d" /opt/smartcore/releases/.env'
# Restart:
ssh root@srv1321059 'cd docker/releases && docker compose --env-file .env restart releases-server'
```

---

## ❌ Revogar ticket de download

> Se um link de download foi vazado, o ticket expira em 5 min por default. Não há revogação antes disso.

**Workaround:** Rotacionar `RELEASES_DOWNLOAD_SECRET` (veja seção acima) — todos os tickets antigos viram inválidos.

---

## 🔍 Logs e Troubleshooting

### Ver logs do container

```bash
docker logs -f smart-core-v2-releases | grep -i "release\|error\|warn"
```

### Verificar saúde

```bash
curl -w '\n' http://localhost:8086/health
# Esperado: 200 OK
```

### Métrica de uploads

```bash
curl -s http://localhost:8086/metrics | grep -i "release_upload"
```

### Arquivo não encontrado na pasta

```bash
# No servidor:
ls -lh /opt/smartcore/releases/v0.1.0/
# Esperado: *.nupkg, Setup.exe, RELEASES (manifesto)
```

---

## 📊 Monitoramento em Produção

### Dashboard Grafana

- URL: `https://grafana.smartcoreassistant.com.br`
- Painel: `Releases — Smart Core Windows`
- Alertas: 3 regras ativas
  1. Upload failures (5/5 min)
  2. Download rate limit hits (> 10/min/IP)
  3. Server heartbeat (timed out > 2 min)

### Alerta por e-mail

- Destinatário: `suporte@smartcoreassistant.com.br`
- Sender: Grafana (via Brevo SMTP)
- Teste: No Grafana, painel Releases → Contact point → Test

---

## 🔐 Segurança Checklist

- [ ] `.env` tem permissão 600 (`chmod 600 /opt/smartcore/releases/.env`)
- [ ] `RELEASES_UPLOAD_TOKEN` não é hardcodeado
- [ ] Tickets HMAC expiram em 5 min (TTL não foi aumentado)
- [ ] ServeDir usa allowlist (nada de `/*`)
- [ ] Logs não contêm token/segredo (verificar `docker logs`)
- [ ] Rate limit ativo (30/min/IP downloads, 5/min upload)

---

## 🚨 Incident Response

### Crash do container

```bash
docker logs smart-core-v2-releases | tail -50
docker restart smart-core-v2-releases
curl http://localhost:8086/health  # Verificar volta
```

### Disco cheio

```bash
du -sh /opt/smartcore/releases/
# Limpar versões antigas:
ssh root@srv1321059 'find /opt/smartcore/releases/v* -mtime +90 -delete'
```

### Taxa de erro alta (> 5% uploads)

1. Verificar token: `echo $RELEASES_UPLOAD_TOKEN | wc -c` (deve ser 64+)
2. Verificar espaço: `df /opt/smartcore/releases`
3. Ver erro específico: `docker logs smart-core-v2-releases | grep "error\|failed"`

---

## 📚 Referências

- [Velopack Docs](https://docs.velopack.io)
- [Plano Windows Releases](../windows-releases-v01-beta.md)
- Smart Core Admin: `https://dev.smartcoreassistant.com.br/v2/admin`
- Releases Server: `https://releases.smartcoreassistant.com.br/health`

---

**Última atualização:** 2026-10-03 | Autor: Claude Code PREVC
