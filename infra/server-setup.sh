#!/usr/bin/env bash
# =============================================================================
# Provisionamento do servidor Hostinger KVM2 — Smart Core Assistant v2
# Executar como root: bash server-setup.sh
#
# O que este script faz:
#   1. Atualiza pacotes do sistema
#   2. Instala Caddy (reverse proxy + TLS automático)
#   3. Instala Rust toolchain (para builds e sqlx-cli)
#   4. Cria usuários e estrutura de diretórios
#   5. Configura firewall (ufw)
#   6. Configura tmpfiles.d para /run/smartcore*
#   7. Instala sqlx-cli no shared
#   8. Exibe próximos passos
# =============================================================================
set -euo pipefail

SMARTCORE_DIR="/opt/smartcore"
RUN_DIR_PROD="/run/smartcore"
RUN_DIR_DEV="/run/smartcore-dev"

echo "============================================================"
echo " Smart Core Assistant v2 — Server Setup"
echo " Servidor: $(hostname) | $(date)"
echo "============================================================"

# ── 1. Pacotes do sistema ─────────────────────────────────────────────────────
echo ""
echo "[1/8] Atualizando pacotes do sistema..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git unzip \
    build-essential pkg-config \
    libssl-dev \
    ufw \
    jq \
    ca-certificates gnupg lsb-release \
    postgresql-client \
    protobuf-compiler

# ── 2. Caddy (reverse proxy) ──────────────────────────────────────────────────
echo ""
echo "[2/8] Instalando Caddy..."
apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
apt-get update -qq && apt-get install -y -qq caddy
# O Caddy roda como user 'caddy'; o diretório de logs precisa ser dele, senão
# um novo bloco `log` no Caddyfile falha o reload com "permission denied".
mkdir -p /var/log/caddy
chown -R caddy:caddy /var/log/caddy

# Snippets de site versionados (ex.: infra/caddy/admin.caddy → painel admin).
# O Caddyfile principal os carrega via `import /etc/caddy/conf.d/*.caddy`.
# Copie os snippets do repo para cá e garanta o import:
#   cp infra/caddy/*.caddy /etc/caddy/conf.d/
#   grep -qF 'import /etc/caddy/conf.d/' /etc/caddy/Caddyfile || \
#     sed -i '1i import /etc/caddy/conf.d/*.caddy\n' /etc/caddy/Caddyfile
#   caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
mkdir -p /etc/caddy/conf.d

# ── 3. Rust toolchain ─────────────────────────────────────────────────────────
echo ""
echo "[3/8] Instalando Rust toolchain (pode demorar alguns minutos)..."
if ! command -v cargo &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --no-modify-path
fi
# shellcheck disable=SC1090
source "$HOME/.cargo/env"
rustup update stable
echo "Rust: $(rustc --version)"

# sqlx-cli para rodar migrations manualmente em emergência
echo "Instalando sqlx-cli..."
cargo install sqlx-cli --no-default-features --features postgres --quiet

# Instalando compilador flatc atualizado para compilação de FlatBuffers
echo "Instalando flatc v25.12.19 do GitHub..."
wget -q -O /tmp/flatc.zip https://github.com/google/flatbuffers/releases/download/v25.12.19-2026-02-06-03fffb2/Linux.flatc.binary.g%2B%2B-13.zip
unzip -q -o /tmp/flatc.zip -d /tmp/flatc_extracted
mv /tmp/flatc_extracted/flatc /usr/local/bin/flatc
chmod +x /usr/local/bin/flatc
rm -rf /tmp/flatc.zip /tmp/flatc_extracted
echo "flatc: $(flatc --version)"

# Flutter NÃO é instalado no servidor. O app web é buildado nos workflows de
# deploy em runner GitHub-hosted (ubuntu) e chega aqui como bundle estático já
# pronto (HTML/JS/WASM) — quem serve é o Caddy, sem toolchain. Isso evita ~1.5GB
# de SDK + build pesando na máquina de produção. Ver .github/workflows/deploy-*.yml.
# Se restou uma instalação antiga: rm -rf /home/gh-runner/flutter

# ── 4. Usuários e diretórios ──────────────────────────────────────────────────
echo ""
echo "[4/8] Criando usuários e estrutura de diretórios..."

# Usuário de runtime das aplicações (sem login, sem sudo)
if ! id smartcore &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin smartcore
    echo "Usuário 'smartcore' criado."
fi

# Usuário para o GitHub Actions runner
if ! id gh-runner &>/dev/null; then
    useradd --system --create-home --shell /bin/bash gh-runner
    echo "Usuário 'gh-runner' criado."
fi

# Adicionar gh-runner ao grupo docker (para pg_dump via docker exec)
usermod -aG docker gh-runner

# Estrutura de diretórios
mkdir -p \
    "$SMARTCORE_DIR/dev/bin" \
    "$SMARTCORE_DIR/dev" \
    "$SMARTCORE_DIR/prod/releases" \
    "$SMARTCORE_DIR/shared" \
    "$RUN_DIR_PROD" \
    "$RUN_DIR_DEV" \
    /srv/smart-core-admin/prod \
    /srv/smart-core-admin/dev

# Permissões
chown -R gh-runner:gh-runner "$SMARTCORE_DIR"
chown -R gh-runner:gh-runner /srv/smart-core-admin
chmod -R 755 /srv/smart-core-admin
chown -R smartcore:smartcore "$RUN_DIR_PROD" "$RUN_DIR_DEV"
chmod 755 "$RUN_DIR_PROD" "$RUN_DIR_DEV"

# Instalar sqlx no shared para uso manual
cp "$HOME/.cargo/bin/sqlx" "$SMARTCORE_DIR/shared/sqlx"
chmod +x "$SMARTCORE_DIR/shared/sqlx"

# gh-runner pode fazer systemctl restart nos serviços smartcore (apenas)
cat > /etc/sudoers.d/gh-runner-smartcore << 'EOF'
# Permite que o runner do GitHub Actions gerencie somente os serviços do SmartCore
gh-runner ALL=(ALL) NOPASSWD: \
    /bin/systemctl restart smartcore-*, \
    /bin/systemctl start smartcore-*, \
    /bin/systemctl stop smartcore-*, \
    /bin/systemctl is-active smartcore-*, \
    /bin/journalctl -u smartcore-*
EOF
chmod 440 /etc/sudoers.d/gh-runner-smartcore

# Adicionar cargo ao PATH do gh-runner
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> /home/gh-runner/.bashrc
echo 'source "$HOME/.cargo/env" 2>/dev/null || true' >> /home/gh-runner/.bashrc

# ── 5. Firewall (ufw) ─────────────────────────────────────────────────────────
echo ""
echo "[5/8] Configurando firewall..."
ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP (Caddy → HTTPS redirect)'
ufw allow 443/tcp  comment 'HTTPS gRPC e Web (Caddy TLS)'
ufw allow 443/udp  comment 'HTTP/3 QUIC'
# Portas internas (NÃO expostas externamente):
# 8080/8090 (gRPC), 5434 (PG), 6380/6381 (Redis) → apenas loopback via Caddy/UDS
ufw --force enable
echo "Firewall configurado."

# ── 6. tmpfiles.d (garante /run/smartcore* após reboot) ──────────────────────
echo ""
echo "[6/8] Configurando tmpfiles.d..."
cat > /etc/tmpfiles.d/smartcore.conf << 'EOF'
# Cria /run/smartcore* a cada boot (necessário para sockets UDS)
d /run/smartcore     0755 smartcore smartcore -
d /run/smartcore-dev 0755 smartcore smartcore -
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/smartcore.conf

# ── 7. journald — retenção de 7 dias ─────────────────────────────────────────
echo ""
echo "[7/8] Configurando journald..."
sed -i 's/#SystemMaxUse=/SystemMaxUse=500M/' /etc/systemd/journald.conf
sed -i 's/#MaxRetentionSec=/MaxRetentionSec=7day/' /etc/systemd/journald.conf
systemctl restart systemd-journald

# ── 8. Caddy — instala o Caddyfile versionado (fonte da verdade) ──────────────
echo ""
echo "[8/8] Instalando Caddyfile versionado (infra/Caddyfile)..."
install -m 644 infra/Caddyfile /etc/caddy/Caddyfile
echo "Caddyfile copiado de infra/Caddyfile → /etc/caddy/Caddyfile"
echo "IMPORTANTE: valide os domínios e rode 'caddy validate' antes de iniciar."
systemctl enable caddy
# Não inicia o Caddy agora — DNS precisa estar apontado antes (TLS automático).

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Provisionamento base concluído!"
echo "============================================================"
echo ""
echo "PRÓXIMOS PASSOS (executar na ordem):"
echo ""
echo "  1. Criar banco de dados DEV no PostgreSQL:"
echo "     docker exec smartcore-v2-postgres psql -U smartcore_app \\"
echo "       -c \"CREATE DATABASE smartcore_v2_dev;\""
echo "     docker exec smartcore-v2-postgres psql -U smartcore_app \\"
echo "       -c \"GRANT ALL ON DATABASE smartcore_v2_dev TO smartcore_app;\""
echo ""
echo "  2. Criar usuário admin com BYPASSRLS:"
echo "     docker exec smartcore-v2-postgres psql -U smartcore_app \\"
echo "       -c \"CREATE USER smartcore_admin WITH PASSWORD 'SENHA' BYPASSRLS;\""
echo "     docker exec smartcore-v2-postgres psql -U smartcore_app \\"
echo "       -c \"GRANT ALL PRIVILEGES ON DATABASE smartcore_v2 TO smartcore_admin;\""
echo "     docker exec smartcore-v2-postgres psql -U smartcore_app \\"
echo "       -c \"GRANT ALL PRIVILEGES ON DATABASE smartcore_v2_dev TO smartcore_admin;\""
echo ""
echo "  3. Criar arquivos .env:"
echo "     vim /opt/smartcore/prod/.env"
echo "     vim /opt/smartcore/dev/.env"
echo "     (ver template em smart-agent-config/doc_dev/planejamento/10-plano-cicd-devops.md seção 7)"
echo ""
echo "  4. Instalar arquivos systemd de infra/systemd/*.service:"
echo "     cp infra/systemd/*.service /etc/systemd/system/"
echo "     systemctl daemon-reload"
echo "     systemctl enable smartcore-prod.target smartcore-dev.target"
echo ""
echo "  5. Apontar DNS para este IP ($(hostname -I | awk '{print $1}')):"
echo "     smartcoreassistant.com.br       (apex — admin prod + gRPC-Web prod)"
echo "     dev.smartcoreassistant.com.br   (admin dev + gRPC-Web dev)"
echo "     # (blocos legados api./dev-api./grafana. — manter DNS só se ainda em uso)"
echo ""
echo "  6. Iniciar o Caddy:"
echo "     systemctl start caddy"
echo ""
echo "  7. Registrar GitHub Actions self-hosted runner como usuário gh-runner:"
echo "     su - gh-runner"
echo "     mkdir ~/actions-runner && cd ~/actions-runner"
echo "     # (instruções em: github.com/SEU-ORG/REPO/settings/actions/runners/new)"
echo ""
echo "  8. Subir observabilidade:"
echo "     docker compose -f docker/compose/observability.yml up -d"
echo ""
