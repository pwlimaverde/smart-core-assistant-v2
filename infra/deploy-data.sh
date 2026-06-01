#!/bin/bash
# ============================================
# Script de Deploy - Infraestrutura de Dados v2
# Smart Core Assistant v2
# ============================================
# Execute a partir da pasta infra/:
#   cd infra
#   ./deploy-data.sh
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "============================================"
echo "  DEPLOY DATA - SMART CORE V2 - HOSTINGER"
echo "============================================"
echo -e "${NC}"

# Verificar se .env.deploy existe
if [ ! -f ".env.deploy" ]; then
    echo -e "${RED}Erro: .env.deploy nao encontrado!${NC}"
    echo -e "${YELLOW}Copie .env.deploy.example para .env.deploy e preencha as credenciais.${NC}"
    exit 1
fi

source .env.deploy

# Validar variaveis obrigatorias
for var in HOSTINGER_SSH_HOST HOSTINGER_SSH_USER HOSTINGER_SSH_PORT DEPLOY_PATH \
           POSTGRES_PASSWORD REDIS_PASSWORD MINIO_ROOT_PASSWORD; do
    val="${!var}"
    if [ -z "$val" ] || [[ "$val" == *"DEFINIR"* ]]; then
        echo -e "${RED}Erro: $var nao definido ou ainda com valor placeholder em .env.deploy${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}Conectando ao servidor: $HOSTINGER_SSH_HOST${NC}"

# Criar diretorios no servidor
echo -e "${BLUE}Criando diretorios remotos...${NC}"
ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST "mkdir -p $DEPLOY_PATH/init-scripts"

# Enviar docker-compose.yml
echo -e "${BLUE}Enviando docker-compose...${NC}"
scp -P $HOSTINGER_SSH_PORT ../docker/compose/data.yml $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST:$DEPLOY_PATH/docker-compose.yml

# Enviar .env.deploy como .env no servidor
echo -e "${BLUE}Enviando .env...${NC}"
scp -P $HOSTINGER_SSH_PORT .env.deploy $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST:$DEPLOY_PATH/.env

# Enviar init-scripts
echo -e "${BLUE}Enviando init-scripts...${NC}"
scp -P $HOSTINGER_SSH_PORT ../docker/init-scripts/01-extensions.sql $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST:$DEPLOY_PATH/init-scripts/

# Executar deploy no servidor
echo -e "${BLUE}Iniciando containers no servidor...${NC}"
ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST << ENDSSH
cd $DEPLOY_PATH

echo "Atualizando imagens Docker..."
docker compose pull

echo "Iniciando containers..."
docker compose up -d --remove-orphans

echo "Aguardando containers iniciarem..."
sleep 15

echo "Status dos containers:"
docker compose ps

echo "Uso de recursos:"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'

echo "Limpando imagens antigas..."
docker image prune -af

echo ""
echo "============================================"
echo "  DEPLOY CONCLUIDO COM SUCESSO!"
echo "============================================"
ENDSSH

echo -e "${GREEN}"
echo "============================================"
echo "  DEPLOY REALIZADO COM SUCESSO!"
echo "============================================"
echo -e "${NC}"
echo ""
echo -e "${CYAN}Para conectar localmente ao banco, execute:${NC}"
echo "  ./tunnel.sh"
echo ""
echo -e "${YELLOW}Comandos uteis:${NC}"
echo "  Logs:      ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST 'cd $DEPLOY_PATH && docker compose logs -f'"
echo "  Status:    ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST 'cd $DEPLOY_PATH && docker compose ps'"
echo "  Restart:   ssh -p $HOSTINGER_SSH_PORT $HOSTINGER_SSH_USER@$HOSTINGER_SSH_HOST 'cd $DEPLOY_PATH && docker compose restart'"
echo ""
