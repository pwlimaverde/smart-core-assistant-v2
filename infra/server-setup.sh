#!/usr/bin/env bash
# =============================================================================
# Provisionamento do servidor Hostinger KVM2 (Full-Docker) — Smart Core Assistant v2
# Executar como root: bash server-setup.sh
#
# O que este script faz:
#   1. Atualiza pacotes e garante dependências (curl, git, jq, ufw, ca-certificates)
#   2. Instala Docker e plugin Compose (se ausentes)
#   3. Cria usuários (gh-runner para CI/CD) e adiciona ao grupo docker
#   4. Cria estrutura de diretórios em /opt/smartcore e define permissões
#   5. Configura firewall (ufw) liberando portas externas de borda (80, 443, 443/udp)
#   6. Configura o sudoers para o gh-runner
# =============================================================================
set -euo pipefail

SMARTCORE_DIR="/opt/smartcore"

echo "============================================================"
echo " Smart Core Assistant v2 — Server Setup (Full-Docker)"
echo " Servidor: $(hostname) | $(date)"
echo "============================================================"

# ── 1. Pacotes do sistema ─────────────────────────────────────────────────────
echo ""
echo "[1/6] Atualizando pacotes do sistema..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git jq ufw ca-certificates gnupg lsb-release

# ── 2. Instalação do Docker & Docker Compose ──────────────────────────────────
echo ""
echo "[2/6] Verificando instalação do Docker..."
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo "✓ Docker já instalado: $(docker --version)"
fi

# ── 3. Usuários e Permissões ──────────────────────────────────────────────────
echo ""
echo "[3/6] Criando usuário de deploy (gh-runner)..."

# Usuário para o GitHub Actions runner
if ! id gh-runner &>/dev/null; then
    useradd --system --create-home --shell /bin/bash gh-runner
    echo "✓ Usuário 'gh-runner' criado."
fi

# Adicionar gh-runner ao grupo docker
usermod -aG docker gh-runner
echo "✓ gh-runner adicionado ao grupo docker."

# ── 4. Estrutura de Diretórios ────────────────────────────────────────────────
echo ""
echo "[4/6] Configurando diretórios de aplicação e deploy..."
# Full-Docker: só precisamos dos diretórios de env (segredos por ambiente) e de
# backups do banco. Sem /opt/.../releases (não há binários no host) e sem
# /srv/smart-core-admin (o bundle web vai embutido na imagem edge).
mkdir -p \
    "$SMARTCORE_DIR/dev/env" \
    "$SMARTCORE_DIR/prod/env" \
    "$SMARTCORE_DIR/prod/backups"

# Permissões das pastas para o runner
chown -R gh-runner:gh-runner "$SMARTCORE_DIR"
echo "✓ Pastas e permissões configuradas."

# ── 5. Configuração do Sudoers ────────────────────────────────────────────────
echo ""
echo "[5/6] Configurando regras de sudoers para gh-runner..."
cat > /etc/sudoers.d/gh-runner-smartcore << 'EOF'
# Permite que o runner do GitHub Actions gerencie docker compose sem senha
gh-runner ALL=(ALL) NOPASSWD: \
    /usr/bin/docker compose *
EOF
chmod 440 /etc/sudoers.d/gh-runner-smartcore
echo "✓ Regras do sudoers aplicadas."

# ── 6. Firewall (ufw) ─────────────────────────────────────────────────────────
echo ""
echo "[6/6] Configurando regras do firewall UFW..."
ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   comment 'SSH'
ufw allow 80/tcp   comment 'HTTP (Caddy Borda)'
ufw allow 443/tcp  comment 'HTTPS (Caddy Borda)'
ufw allow 443/udp  comment 'HTTP/3 QUIC'
ufw --force enable
echo "✓ Firewall UFW habilitado."

echo "============================================================"
echo " Provisionamento Full-Docker concluído com sucesso!"
echo "============================================================"
echo ""
echo "PRÓXIMOS PASSOS:"
echo "  1. Configurar os arquivos de ambiente reais no servidor:"
echo "       /opt/smartcore/dev/env/dev.env   (copie de docker/dev/.env.example)"
echo "       /opt/smartcore/prod/env/prod.env (copie de docker/prod/.env.example)"
echo ""
echo "  2. Registrar o GitHub self-hosted runner sob o usuário 'gh-runner'."
echo ""
echo "  3. Subir os composes FUNDACIONAIS primeiro (sobem UMA vez e persistem;"
echo "     criam as redes externas que o deploy do app consome):"
echo "       (cd docker/observability && docker compose up -d)              # rede de observabilidade"
echo "       (cd docker/evolution     && docker compose --env-file .env up -d)  # rede smart_core_v2_evolution_net + gateway WhatsApp"
echo ""
echo "     IMPORTANTE: docker/evolution/.env exige EVOLUTION_POSTGRES_PASSWORD e"
echo "     EVOLUTION_GLOBAL_API_KEY. Sem o evolution no ar, o deploy do docker/dev"
echo "     FALHA: data_whatsapp/webhook_ingress dependem da rede externa"
echo "     'smart_core_v2_evolution_net' criada por esta stack."
echo ""
echo "  4. A partir daí o CI/CD gerencia builds, tags e subidas automáticas de DEV e PROD."
