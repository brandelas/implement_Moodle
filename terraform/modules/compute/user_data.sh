#!/bin/bash
# =============================================================================
# user_data.sh — Script de boot da EC2 (template renderizado por templatefile()
# em main.tf). Executado uma única vez pelo cloud-init no primeiro boot.
#
# Escape: variáveis Bash usam $$ + {VAR}; as demais interpolações são variáveis
# Terraform (rds_endpoint, db_name, moodle_admin_user, moodle_site_name,
# repo_url, repo_branch e as credenciais *_b64).
#
# NOTA: Base64 não é criptografia — apenas evita que caracteres especiais das
# senhas sejam interpretados pelo Bash. As credenciais ficam legíveis no
# Terraform state e no IMDS (protegido por IMDSv2).
#
# TODO: Migrar as credenciais para o AWS Secrets Manager fora do Learner Lab.
# Log de execução: /var/log/user-data-moodle.log
# =============================================================================

set -euo pipefail
exec >> /var/log/user-data-moodle.log 2>&1

echo "=== Inicio do user_data.sh: $(date) ==="

# =============================================================================
# ETAPA 1 — Swap de 2 GB
# A t3.micro tem 1 GB de RAM; o swap evita falta de memória no build da imagem
# Docker e no install.php do Moodle.
# =============================================================================
echo "--- Etapa 1: criar swap ---"
if ! swapon --show | grep -q /swapfile; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

# =============================================================================
# ETAPA 2 — Atualizar pacotes
# =============================================================================
echo "--- Etapa 2: dnf update ---"
dnf update -y

# =============================================================================
# ETAPA 3 — Instalar git e jq
# =============================================================================
echo "--- Etapa 3: instalar git e jq ---"
dnf install -y git jq

# =============================================================================
# ETAPA 4 — Instalar cliente PostgreSQL e validar pg_isready
# pg_isready confirma disponibilidade do servidor PostgreSQL; não valida
# credenciais nem acesso ao banco (autenticação real ocorre no install.php).
# =============================================================================
echo "--- Etapa 4: instalar postgresql15 e validar pg_isready ---"
dnf install -y postgresql15
if ! command -v pg_isready > /dev/null 2>&1; then
  echo "ERRO: pg_isready nao encontrado apos instalar postgresql15."
  exit 1
fi

# =============================================================================
# ETAPA 5 — Instalar Docker; verificar versão >= 24
# =============================================================================
echo "--- Etapa 5: instalar Docker ---"
dnf install -y docker

DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
DOCKER_MAJOR=$(echo "$${DOCKER_VERSION}" | cut -d. -f1)

# O pacote "docker" do Amazon Linux 2023 já fornece Docker >= 24. O repositório
# docker-ce (CentOS/RHEL) não é compatível com o AL2023, por isso não há fallback.
if [ "$${DOCKER_MAJOR:-0}" -lt 24 ]; then
  echo "ERRO: Docker $${DOCKER_VERSION} instalado; versao minima exigida: 24."
  exit 1
fi
echo "Docker $${DOCKER_VERSION} instalado."

# =============================================================================
# ETAPA 6 — Instalar Docker Compose v2
# =============================================================================
echo "--- Etapa 6: instalar Docker Compose v2 ---"
# O pacote docker do AL2023 não inclui o plugin Compose v2; baixa o binário oficial.
if ! docker compose version > /dev/null 2>&1; then
  COMPOSE_RELEASE="v2.30.3"
  COMPOSE_BIN="/usr/libexec/docker/cli-plugins/docker-compose"
  mkdir -p /usr/libexec/docker/cli-plugins
  # --retry: tolera falha temporária de rede ou do GitHub durante o boot.
  curl -fsSL --retry 3 --retry-delay 5 \
    "https://github.com/docker/compose/releases/download/$${COMPOSE_RELEASE}/docker-compose-linux-x86_64" \
    -o "$${COMPOSE_BIN}"
  chmod +x "$${COMPOSE_BIN}"
fi

# =============================================================================
# ETAPA 7 — Verificar versão do Docker Compose >= 2.30
# =============================================================================
echo "--- Etapa 7: verificar versao Docker Compose >= 2.30 ---"
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null | tr -d 'v')
REQUIRED_COMPOSE="2.30.0"
if ! printf "%s\n%s\n" "$${REQUIRED_COMPOSE}" "$${COMPOSE_VERSION}" | sort -V -C 2>/dev/null; then
  echo "ERRO: Docker Compose $${COMPOSE_VERSION} instalado; versao minima exigida: $${REQUIRED_COMPOSE}."
  exit 1
fi
echo "Docker Compose $${COMPOSE_VERSION} OK."

# =============================================================================
# ETAPA 8 — Adicionar ec2-user ao grupo docker
# =============================================================================
echo "--- Etapa 8: adicionar ec2-user ao grupo docker ---"
usermod -aG docker ec2-user

# =============================================================================
# ETAPA 9 — Habilitar e iniciar Docker
# =============================================================================
echo "--- Etapa 9: systemctl enable --now docker ---"
systemctl enable --now docker

# =============================================================================
# ETAPA 10 — Obter EC2_DNS via IMDSv2
# Executado antes de qualquer uso do DNS (wwwroot do Moodle).
# $${TOKEN} e $${EC2_DNS} são variáveis Bash escapadas no template.
# =============================================================================
echo "--- Etapa 10: obter EC2_DNS via IMDSv2 ---"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
EC2_DNS=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
  "http://169.254.169.254/latest/meta-data/public-hostname")

if [ -z "$${EC2_DNS}" ]; then
  echo "ERRO: EC2_DNS vazio — falha ao obter public-hostname via IMDSv2."
  exit 1
fi
echo "EC2_DNS obtido com sucesso."

# =============================================================================
# ETAPA 11 — Clonar repositório
# =============================================================================
echo "--- Etapa 11: clonar repositorio ---"
git clone --depth 1 --branch "${repo_branch}" "${repo_url}" /opt/moodle

# =============================================================================
# ETAPA 12 — Decodificar credenciais Base64
# Os valores decodificados nunca são impressos no log.
# =============================================================================
echo "--- Etapa 12: decodificar credenciais ---"
DB_PASSWORD=$(echo "${db_password_b64}" | base64 -d)
DB_USERNAME=$(echo "${db_username_b64}" | base64 -d)
MOODLE_ADMIN_PASS=$(echo "${moodle_admin_pass_b64}" | base64 -d)

# =============================================================================
# ETAPA 13 — Gerar /opt/moodle/docker/.env com chmod 600
# printf "%s\n" para senhas evita interpretação de \n, -e etc.
# Nenhuma credencial é impressa no log.
# =============================================================================
echo "--- Etapa 13: gerar .env ---"
{
  echo "POSTGRES_DB=${db_name}"
  echo "POSTGRES_USER=$${DB_USERNAME}"
  printf "POSTGRES_PASSWORD=%s\n" "$${DB_PASSWORD}"
  echo "MOODLE_DATABASE_HOST=${rds_endpoint}"
  echo "MOODLE_DATABASE_PORT_NUMBER=5432"
  echo "MOODLE_DATABASE_NAME=${db_name}"
  echo "MOODLE_DATABASE_USER=$${DB_USERNAME}"
  printf "MOODLE_DATABASE_PASSWORD=%s\n" "$${DB_PASSWORD}"
  echo "MOODLE_USERNAME=${moodle_admin_user}"
  printf "MOODLE_PASSWORD=%s\n" "$${MOODLE_ADMIN_PASS}"
  echo "MOODLE_SITE_NAME=${moodle_site_name}"
} > /opt/moodle/docker/.env
chmod 600 /opt/moodle/docker/.env

# =============================================================================
# ETAPA 14 — Aguardar RDS com pg_isready (sem -U)
# pg_isready verifica disponibilidade do servidor; não valida autenticação.
# A autenticação real ocorre no install.php.
# =============================================================================
echo "--- Etapa 14: aguardar RDS ---"
RETRIES=30
WAIT=10
RDS_READY=0
for i in $(seq 1 $${RETRIES}); do
  if pg_isready -h "${rds_endpoint}" -p 5432; then
    RDS_READY=1
    break
  fi
  echo "RDS nao disponivel, tentativa $${i}/$${RETRIES}..."
  sleep $${WAIT}
done

if [ "$${RDS_READY}" -eq 0 ]; then
  echo "ERRO: RDS nao ficou disponivel apos $${RETRIES} tentativas."
  exit 1
fi
echo "RDS disponivel."

# =============================================================================
# ETAPA 15 — Iniciar Moodle com Docker Compose de produção
# =============================================================================
echo "--- Etapa 15: docker compose up -d ---"
COMPOSE_FILE=/opt/moodle/terraform/modules/compute/docker-compose.prod.yml
docker compose -f "$${COMPOSE_FILE}" up -d

# =============================================================================
# ETAPA 16 — Aguardar Apache responder em localhost:80 (timeout 120s)
# =============================================================================
echo "--- Etapa 16: aguardar Apache ---"
APACHE_READY=0
for i in $(seq 1 24); do
  if curl -s -o /dev/null -w "%%{http_code}" http://localhost:80 | grep -q "^[23]"; then
    APACHE_READY=1
    break
  fi
  echo "Apache nao respondeu, tentativa $${i}/24..."
  sleep 5
done

if [ "$${APACHE_READY}" -eq 0 ]; then
  echo "ERRO: Apache nao respondeu em 120s."
  exit 1
fi
echo "Apache respondendo."

# =============================================================================
# ETAPA 17 — Lógica de dois caminhos: instalação inicial ou verificação
# =============================================================================
echo "--- Etapa 17: verificar config.php ---"

if docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    test -f /var/www/html/config.php 2>/dev/null; then

  # ── CAMINHO B: config.php já existe ──────────────────────────────────────
  echo "config.php ja existe. Pulando instalacao."

  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      php -l /var/www/html/config.php > /dev/null 2>&1; then
    echo "ERRO: config.php existente tem sintaxe invalida."
    exit 1
  fi

  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      grep -q "${rds_endpoint}" /var/www/html/config.php; then
    echo "ERRO: config.php nao contem o hostname do RDS esperado."
    exit 1
  fi

  echo "=== Moodle ja configurado — verificacoes OK: $(date) ==="

else

  # ── CAMINHO A: instalação inicial ────────────────────────────────────────

  # a) Permissões temporárias para www-data criar config.php
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown www-data:www-data /var/www/html
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 755 /var/www/html

  # b) /var/moodledata: www-data com leitura e escrita (permanente)
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown www-data:www-data /var/moodledata
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 770 /var/moodledata

  # c) Executar instalador como www-data
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T --user www-data moodle \
      php /var/www/html/admin/cli/install.php \
      --non-interactive \
      --lang=pt_br \
      --wwwroot="http://$${EC2_DNS}" \
      --dataroot=/var/moodledata \
      --dbtype=pgsql \
      --dbhost="${rds_endpoint}" \
      --dbname="${db_name}" \
      --dbuser="$${DB_USERNAME}" \
      --dbpass="$${DB_PASSWORD}" \
      --fullname="${moodle_site_name}" \
      --shortname="moodle" \
      --adminuser="${moodle_admin_user}" \
      --adminpass="$${MOODLE_ADMIN_PASS}" \
      --adminemail="admin@example.com" \
      --agree-license; then
    echo "ERRO: install.php saiu com erro."
    exit 1
  fi

  # d) Verificar sintaxe PHP do config.php gerado
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      php -l /var/www/html/config.php > /dev/null 2>&1; then
    echo "ERRO: config.php gerado tem sintaxe invalida."
    exit 1
  fi

  # d) Confirmar hostname do RDS no config.php gerado
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      grep -q "${rds_endpoint}" /var/www/html/config.php; then
    echo "ERRO: config.php nao contem o hostname do RDS esperado."
    exit 1
  fi

  # e) Reverter /var/www/html para root somente após verificações passarem
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown root:www-data /var/www/html
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 755 /var/www/html
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown root:www-data /var/www/html/config.php
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 640 /var/www/html/config.php

  # ==========================================================================
  # ETAPA 18 — Registrar sucesso
  # ==========================================================================
  echo "=== Moodle instalado com sucesso: $(date) ==="

fi
