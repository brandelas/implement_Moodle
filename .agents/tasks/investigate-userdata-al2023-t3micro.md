# Relatório de Investigação: user_data.sh × Amazon Linux 2023 × t3.micro

**Escopo:** `terraform/modules/compute/user_data.sh`, `docker-compose.prod.yml`, `docker/Dockerfile`, `terraform/modules/compute/main.tf`, `terraform/modules/database/main.tf`  
**Instância-alvo:** `t3.micro` (1 GB RAM), Amazon Linux 2023  
**Modo:** Somente leitura — nenhum arquivo foi alterado  
**Data:** 2025

---

## Resumo Executivo

O script `user_data.sh` foi bem projetado para o seu contexto educacional e evita os erros mais comuns documentados em outros projetos similares. Os pontos mais críticos são: **(1)** o `docker compose version` é executado antes do daemon Docker estar em execução, podendo causar falha silenciosa no `set -euo pipefail`; **(2)** o `docker build` é executado sem nenhuma restrição de memória dentro de um container com apenas 1 GB de RAM + 2 GB de swap, sem parâmetros de memória no Compose; **(3)** a idempotência depende exclusivamente da presença de `config.php` dentro do contêiner, que se perde em um `docker compose down`. Todos os itens restantes são de severidade média ou baixa.

---

## Classificação por Severidade

---

## 🔴 CRÍTICO

### C-01 — `docker compose version` executado antes do daemon Docker iniciar

**Arquivo:** `terraform/modules/compute/user_data.sh`, Etapa 6 (linha ~84) e Etapa 7 (linha ~99)  
**Construção problemática:**
```bash
# Etapa 6:
if ! docker compose version > /dev/null 2>&1; then
  ...binário baixado...
fi

# Etapa 7 (verificação de versão):
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null | tr -d 'v')
```
O Docker daemon só é iniciado na **Etapa 9** (`systemctl enable --now docker`). As Etapas 6 e 7 invocam `docker compose version` **antes** de `systemctl enable --now docker`. Com `set -euo pipefail` ativo, qualquer subshell que retorne código de saída não-zero mata o script.

Na prática: `docker compose version` antes do socket `/var/run/docker.sock` existir retorna erro com `Cannot connect to the Docker daemon`. O `> /dev/null 2>&1` suprime a saída mas **não suprime o código de saída** — a condição `if !` inverte: o bloco é executado (correto). Mas na **Etapa 7**, `docker compose version --short 2>/dev/null` retorna código de saída 1 com saída vazia; `COMPOSE_VERSION` fica vazio; `sort -V -C` com string vazia vs "2.30.0" provavelmente retorna 1; o bloco de erro é acionado e o script morre com `exit 1`.

**Risco:** falha total do boot antes da instalação do Moodle. O log `/var/log/user-data-moodle.log` vai mostrar "ERRO: Docker Compose  instalado; versao minima exigida: 2.30.0" com versão em branco.

**Correção sugerida:** mover as Etapas 6 e 7 para **depois** da Etapa 9 (`systemctl enable --now docker`), ou substituir a verificação de versão pré-serviço por uma inspeção do binário diretamente: `/usr/libexec/docker/cli-plugins/docker-compose version --short`.

---

## 🟠 ALTO

### A-01 — `docker build` sem controle de memória em 1 GB de RAM + 2 GB de swap

**Arquivo:** `terraform/modules/compute/docker-compose.prod.yml`  
**Construção problemática:**
```yaml
services:
  moodle:
    build:
      context: ../../../docker
      dockerfile: Dockerfile
```
O `Dockerfile` compila extensões PHP (`mbstring`, `intl`, `gd`, `sodium`, `zip`, `pdo_pgsql`, `opcache`, `curl`, `simplexml`) em múltiplas camadas `RUN`, além de baixar o Moodle 4.1 (~60 MB) e fazer `cp -r` de ~300 MB de arquivos para `/var/www/html`. Nenhum parâmetro de memória (`mem_limit`, `--memory`, `shm_size`) é definido no Compose de produção.

O build pode ultrapassar 2 GB de consumo combinado (RAM + swap) durante os passos `docker-php-ext-install intl` e `docker-php-ext-install gd`, que compilam C. Com swap em disco gp3, isso prolonga drasticamente o build (potencial timeout de cloud-init) e pode causar OOM killer caso o pico ultrapasse os 3 GB.

**Agravante:** `opcache.memory_consumption=256` (configurado no `Dockerfile`) reserva 256 MB do heap PHP por processo Apache, o que reduz a RAM efetivamente disponível para o build se o contêiner já estiver rodando.

**Risco:** OOM durante o build → contêiner morto → Etapa 16 (loop de espera Apache) esgota timeout de 120 s → `exit 1` → boot falha.

**Correção sugerida:** adicionar `mem_limit: 2g` e `memswap_limit: 3g` ao serviço no `docker-compose.prod.yml`. Alternativamente, fazer pré-build da imagem fora da instância (CI/CD) e usar pull ao invés de build.

---

### A-02 — Idempotência frágil: `config.php` não persiste fora do contêiner

**Arquivo:** `terraform/modules/compute/user_data.sh`, Etapa 17  
**Construção problemática:**
```bash
if docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    test -f /var/www/html/config.php 2>/dev/null; then
  # Pula instalação
else
  # Executa install.php
fi
```
O `config.php` é criado dentro da camada gravável do contêiner Docker em `/var/www/html`. O volume `moodle_www` está montado em `/var/moodledata`, **não** em `/var/www/html`. Isso significa que `config.php` é destruído toda vez que o contêiner é recriado (`docker compose down && docker compose up`).

Como o `user_data.sh` só executa no **primeiro boot** da EC2, em reboots subsequentes o Docker é reiniciado pelo systemd (porque `restart: unless-stopped`), e o contêiner já existe — `config.php` está preservado. O risco ocorre em cenários operacionais onde `docker compose down` é executado manualmente.

**Situação mais grave:** se a EC2 for destruída e recriada (`terraform destroy` + `apply`), o `install.php` tentará rodar sobre um banco RDS **já inicializado**. O instalador CLI do Moodle não é idempotente — ele falha se as tabelas já existem.

**Risco:** reinstalação sobre banco existente → erro do `install.php` → `exit 1` → instância inutilizável sem intervenção manual.

**Correção sugerida:** persistir `config.php` em um volume nomeado separado ou em um bind mount no host (ex.: `/opt/moodle-config/config.php`) e copiá-lo para dentro do contêiner na inicialização.

---

### A-03 — `dnf update -y` antes do swap (Etapa 2 antes da Etapa 1 ser persistida)

**Arquivo:** `terraform/modules/compute/user_data.sh`, linhas 29–42  
**Construção problemática:**
```bash
# Etapa 1 — cria swap
dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
...
swapon /swapfile

# Etapa 2 — dnf update -y
dnf update -y
```
O swap **é** criado antes do `dnf update` — a ordem está correta nesse aspecto. O problema é diferente: o `dd` grava 2 GB em disco com `bs=1M count=2048`. Em uma instância `t3.micro` com disco `gp3` de 16 GB e throughput padrão de 125 MB/s, isso leva aproximadamente **16 segundos** — aceitável. O risco real é que, se o disco raiz estiver cheio ou com menos de 2 GB livres, o `dd` falha com `No space left on device` e o script morre imediatamente sem mensagem de erro clara (a flag `status=none` suprime a saída do `dd`).

Com `root_volume_size = 16` GB (padrão), o AL2023 usa ~3 GB na AMI base. Sobram ~11 GB para o swapfile de 2 GB + imagem Docker de ~1,5 GB + moodledata. O risco de espaço é baixo, mas a ausência de verificação prévia de espaço em disco é uma fragilidade de diagnóstico.

**Risco secundário:** `vm.swappiness` não é configurado; o padrão do AL2023 é 60, que ativa o swap apenas quando a RAM está a 60% de uso. Para um workload de build Docker, isso pode causar swapping tardio e OOM antes de usar o swap. Para garantir uso ativo do swap, `sysctl vm.swappiness=10` (reduz preferência por swap) ou `vm.swappiness=80` (força uso mais agressivo) deve ser configurado conforme a necessidade.

---

### A-04 — Timeout implícito do cloud-init pode abortar o boot

**Arquivo:** `terraform/modules/compute/user_data.sh` (todo o script)  
**Descrição:** O cloud-init no Amazon Linux 2023 não tem um timeout padrão documentado fixo para user data scripts, mas no contexto do AWS Academy Learner Lab (sessões limitadas a 4 horas) a instância pode ser encerrada antes do boot completar se o script demorar demais.

O tempo estimado de execução completa do script é:
- `dnf update -y`: 60–120 s
- `docker compose up -d` (inclui `docker build`): 5–15 minutos (compilação de extensões PHP)
- RDS wait loop: até 300 s (30 × 10 s)
- Apache wait loop: até 120 s (24 × 5 s)
- `install.php`: 60–180 s

**Total estimado: 8–20 minutos.** O cloud-init não tem um timeout que interromperia isso, mas o build Docker sem controle de memória (ver A-01) pode demorar muito mais em um `t3.micro` usando swap.

Não existe logging de progresso fora do arquivo `/var/log/user-data-moodle.log`. Se o script travar em silêncio (ex.: `dd` em disco cheio com `status=none`), não há alertas visíveis.

**Risco:** boot aparentemente bem-sucedido (instância no estado `running`) mas Moodle não disponível, sem feedback ao operador além do log manual via SSH.

---

## 🟡 MÉDIO

### M-01 — `docker compose version` invocado sem daemon ativo (duplicata de C-01, aspectos adicionais)

**Arquivo:** `user_data.sh`, Etapa 6, linha ~84  
O binário baixado em `/usr/libexec/docker/cli-plugins/docker-compose` é o plugin correto para `docker compose` (v2). A verificação `if ! docker compose version > /dev/null 2>&1; then` testa se o plugin já existe funcionando. Com o daemon parado, isso nunca é verdade — o plugin sempre é baixado. Isso desperdiça largura de banda no boot e ignora se um plugin defeituoso está instalado.

**Risco menor:** tráfego desnecessário; plugin já existente sobrescrito desnecessariamente.

---

### M-02 — `.env` escrito em `/opt/moodle/docker/.env` mas docker-compose.prod.yml referencia `../../../docker/.env`

**Arquivo:** `docker-compose.prod.yml`, linha 23; `user_data.sh`, linha 168  
O Compose de produção está em `/opt/moodle/terraform/modules/compute/docker-compose.prod.yml`. O caminho relativo `../../../docker/.env` resolve para `/opt/moodle/docker/.env`.  
O `user_data.sh` escreve em `/opt/moodle/docker/.env`.  
**Os caminhos coincidem.** Não há erro de caminho — mas a lógica depende de o repositório ser clonado exatamente em `/opt/moodle` e do `docker-compose.prod.yml` estar em `terraform/modules/compute/` dentro do clone. Se o nome do repositório mudar ou o clone falhar parcialmente, o `.env` não será encontrado e o `docker compose up -d` falhará silenciosamente (Compose levanta o serviço sem `.env` apenas com aviso, não com erro).

**Risco:** falha discreta de configuração sem `exit 1` imediato do Compose.

---

### M-03 — Ausência de verificação de espaço em disco antes do `dd`

**Arquivo:** `user_data.sh`, Etapa 1, linha 30  
```bash
dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
```
A flag `status=none` suprime qualquer mensagem de erro do `dd`. Se o disco estiver cheio, `dd` retornará código de saída não-zero e o `set -e` vai matar o script, mas sem mensagem explicativa no log. Um `df -h /` antes do `dd` tornaria o diagnóstico muito mais claro.

---

### M-04 — Sem `swappiness` configurado; comportamento do kernel pode não usar swap agressivamente

**Arquivo:** `user_data.sh` (ausente)  
O padrão `vm.swappiness=60` do AL2023 é adequado para servidores de uso geral, mas para um workload de build Docker que pode exaurir a RAM rapidamente, um valor mais alto (ex.: 80) garantiria que o kernel movesse páginas para swap antes de acionar o OOM killer. Isso é especialmente relevante na Etapa 15 (`docker compose up -d` que dispara o build).

**Risco:** OOM killer antes de o swap ser usado efetivamente.

---

### M-05 — `install.php` passa `--dbtype=pgsql` mas Dockerfile instala apenas `pdo_pgsql`

**Arquivo:** `docker/Dockerfile`, linha 75; `user_data.sh`, Etapa 17  
O `install.php` recebe `--dbtype=pgsql`. O Moodle usa seu próprio driver ADOdb e a extensão PDO é o mecanismo subjacente. O `Dockerfile` instala `pdo_pgsql` (correto para PostgreSQL). **Não há `pdo_mysql` instalado**, o que é adequado para este stack. Nenhum erro aqui, mas vale confirmar: o Moodle 4.1 requer `pdo_pgsql` para `--dbtype=pgsql`, e ele está presente.

**Risco:** nenhum — situação correta, mencionado apenas para completude da auditoria.

---

### M-06 — Credenciais em Base64 no Terraform state e no IMDS (risco de segurança)

**Arquivo:** `terraform/modules/compute/main.tf`, linhas 95–105  
```hcl
user_data = templatefile("${path.module}/user_data.sh", {
  db_password_b64       = base64encode(var.db_password)
  db_username_b64       = base64encode(var.db_username)
  moodle_admin_pass_b64 = base64encode(var.moodle_admin_password)
  ...
})
```
O script renderizado (com credenciais em Base64) é armazenado em texto claro no `terraform.tfstate` e acessível via `http://169.254.169.254/latest/user-data` (protegido por IMDSv2, mas não criptografado). Base64 é reversível trivialmente com `base64 -d`.

O design documenta esse risco explicitamente (D-07) e o `TODO` no cabeçalho do script menciona a migração para AWS Secrets Manager. Para o escopo educacional (Learner Lab), a mitigação disponível (IMDSv2 + restrição SSH) é adequada.

**Risco:** exposição de credenciais se o state for commitado ou se a instância for comprometida.

---

### M-07 — `docker compose -f ... exec -T moodle` falha se o contêiner não estiver saudável

**Arquivo:** `user_data.sh`, Etapa 17  
O Compose de produção (`docker-compose.prod.yml`) **não define `healthcheck`** para o serviço `moodle`. A Etapa 16 espera que o Apache responda com HTTP 2xx/3xx em `localhost:80`, o que é uma verificação de disponibilidade de porta. No entanto, `docker compose exec` pode funcionar mesmo com Apache respondendo na porta se o PHP não estiver pronto ainda. O `install.php` pode falhar por razões de PHP não inicializado, embora isso seja raro na prática.

**Risco:** falha intermitente do `install.php` em instâncias lentas.

---

## 🟢 BAIXO

### B-01 — `dnf install -y docker` instala versão do Amazon Linux 2023 (correto, sem fallback necessário)

**Arquivo:** `user_data.sh`, Etapa 5, linha 65  
O script usa `dnf install -y docker`, que no AL2023 instala o pacote `docker` fornecido pela Amazon (baseado no Docker CE upstream). Em maio de 2025, esse pacote entrega Docker 25.x ou superior, satisfazendo o requisito de versão >= 24. O comentário no script menciona corretamente que o repositório `docker-ce` do CentOS/RHEL **não é compatível** com AL2023.

A verificação de versão pós-instalação é correta:
```bash
DOCKER_MAJOR=$(echo "$${DOCKER_VERSION}" | cut -d. -f1)
if [ "$${DOCKER_MAJOR:-0}" -lt 24 ]; then exit 1; fi
```
**Situação:** sem problemas. O `amazon-linux-extras` (removido no AL2023) não é referenciado em lugar nenhum. Uso de `yum` também ausente. A migração para `dnf` está correta.

---

### B-02 — Docker Compose v2 instalado como plugin CLI (correto)

**Arquivo:** `user_data.sh`, Etapa 6, linhas 85–92  
```bash
COMPOSE_BIN="/usr/libexec/docker/cli-plugins/docker-compose"
mkdir -p /usr/libexec/docker/cli-plugins
curl -fsSL --retry 3 --retry-delay 5 \
  "https://github.com/docker/compose/releases/download/$${COMPOSE_RELEASE}/docker-compose-linux-x86_64" \
  -o "$${COMPOSE_BIN}"
chmod +x "$${COMPOSE_BIN}"
```
O binário é instalado no diretório correto de plugins do Docker CLI (`/usr/libexec/docker/cli-plugins/`), permitindo o uso como `docker compose` (v2) em vez de `docker-compose` (v1 legado). A versão fixada em `v2.30.3` satisfaz o requisito mínimo de `format: raw` no Compose (disponível a partir de 2.30). **Situação correta.**

---

### B-03 — `pg_isready` sem `-U` evita falso positivo de autenticação

**Arquivo:** `user_data.sh`, Etapa 14  
```bash
if pg_isready -h "${rds_endpoint}" -p 5432; then
```
Correto. `pg_isready` sem `-U` testa somente conectividade TCP — não tenta autenticar. A autenticação real ocorre no `install.php`. Usar `-U` aqui causaria falsos negativos se o usuário ainda não existisse no RDS.

---

### B-04 — `--retry 3` no curl do Compose mitiga falhas transitórias de rede

**Arquivo:** `user_data.sh`, Etapa 6, linha 87  
O GitHub pode retornar 429 ou erros de rede durante o boot de muitas instâncias simultâneas. As flags `--retry 3 --retry-delay 5` protegem contra isso. Adequado.

---

### B-05 — `format: raw` no env_file do Compose protege caracteres especiais nas senhas

**Arquivo:** `docker-compose.prod.yml`, linha 23–24  
```yaml
env_file:
  - path: ../../../docker/.env
    format: raw
```
Correto. Sem `format: raw`, o Docker Compose interpola variáveis com `$` nos valores do `.env`, corrompendo senhas com caracteres especiais. A dependência de Compose >= 2.30 está coberta pelo check da Etapa 7 (quando funcionando corretamente — ver C-01).

---

### B-06 — IMDSv2 habilitado (`http_tokens = "required"`)

**Arquivo:** `terraform/modules/compute/main.tf`, linhas 81–85  
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}
```
O script obtém o token corretamente na Etapa 10 com `-X PUT` e o header `X-aws-ec2-metadata-token-ttl-seconds`. Correto.

---

### B-07 — IAM: LabRole/LabInstanceProfile cobre as permissões necessárias

**Arquivo:** `terraform/modules/compute/main.tf`, linha 78  
O script não usa ECR, SSM nem Secrets Manager — tudo é passado via `user_data` ou clonado de um repositório público HTTPS. A `LabRole` fornece permissões de EC2, S3 e DynamoDB suficientes para o escopo. Nenhuma permissão IAM adicional é necessária para o fluxo atual.

**Nota:** o `TODO` no cabeçalho do `user_data.sh` menciona migração para Secrets Manager no futuro, o que exigiria adicionar `secretsmanager:GetSecretValue` à `LabRole` — mas isso não é bloqueante para o fluxo atual.

---

### B-08 — Falta de pacotes no host EC2 (PHP, curl, unzip) não é problema

**Arquivo:** `user_data.sh` (ausente)  
PHP CLI, curl e unzip **não** precisam ser instalados no host EC2 — todas as operações PHP e de download são feitas dentro do contêiner Docker (via `docker compose exec`). O `install.php` é executado com `docker compose exec -T --user www-data moodle php ...`. Os únicos pacotes que precisam estar no host são: `git` (clone do repo), `postgresql15` (para `pg_isready`) e `jq` (utilitário) — todos instalados nas Etapas 3 e 4. **Situação correta.**

---

## Tabela Resumida de Riscos

| ID | Severidade | Título | Arquivo | Probabilidade de Falha no Boot |
|----|-----------|--------|---------|-------------------------------|
| C-01 | 🔴 Crítico | `docker compose version` antes do daemon iniciar | `user_data.sh` Etapa 6–7 | Alta |
| A-01 | 🟠 Alto | Build sem controle de memória em 1 GB RAM + 2 GB swap | `docker-compose.prod.yml` | Média |
| A-02 | 🟠 Alto | Idempotência frágil: `config.php` não persiste fora do contêiner | `user_data.sh` Etapa 17 | Baixa (boot inicial) / Alta (recriação EC2) |
| A-03 | 🟠 Alto | `dd` sem verificação de espaço; `status=none` suprime erros | `user_data.sh` Etapa 1 | Baixa |
| A-04 | 🟠 Alto | Timeout implícito do cloud-init; boot pode demorar 15–20 min | `user_data.sh` (global) | Baixa (Learner Lab OK) |
| M-01 | 🟡 Médio | Plugin Compose baixado desnecessariamente sem daemon ativo | `user_data.sh` Etapa 6 | Baixa |
| M-02 | 🟡 Médio | Caminho do `.env` dependente de clone exato em `/opt/moodle` | `docker-compose.prod.yml` | Baixa (repo público fixo) |
| M-03 | 🟡 Médio | Ausência de check de espaço antes do `dd` | `user_data.sh` Etapa 1 | Baixa |
| M-04 | 🟡 Médio | `vm.swappiness` padrão pode não ativar swap agressivamente | `user_data.sh` (ausente) | Baixa |
| M-05 | 🟡 Médio | `pdo_pgsql` correto; sem `pdo_mysql` (esperado) | `Dockerfile` linha 75 | Nenhuma |
| M-06 | 🟡 Médio | Credenciais em Base64 no state e IMDS (risco de segurança) | `main.tf` linhas 95–105 | N/A (segurança) |
| M-07 | 🟡 Médio | Sem `healthcheck` no serviço Compose; exec pode ser prematuro | `docker-compose.prod.yml` | Baixa |
| B-01 | 🟢 Baixo | `dnf install -y docker` correto para AL2023 | `user_data.sh` Etapa 5 | Nenhuma |
| B-02 | 🟢 Baixo | Compose v2 instalado como plugin CLI (correto) | `user_data.sh` Etapa 6 | Nenhuma |
| B-03 | 🟢 Baixo | `pg_isready` sem `-U` (correto) | `user_data.sh` Etapa 14 | Nenhuma |
| B-04 | 🟢 Baixo | `--retry 3` no curl do Compose | `user_data.sh` Etapa 6 | Nenhuma |
| B-05 | 🟢 Baixo | `format: raw` protege senhas no Compose | `docker-compose.prod.yml` linha 24 | Nenhuma |
| B-06 | 🟢 Baixo | IMDSv2 corretamente configurado | `main.tf` linhas 81–85 | Nenhuma |
| B-07 | 🟢 Baixo | LabRole cobre permissões IAM necessárias | `main.tf` linha 78 | Nenhuma |
| B-08 | 🟢 Baixo | Sem necessidade de PHP/curl no host EC2 | `user_data.sh` (ausente) | Nenhuma |

---

## Respostas às Perguntas da Investigação

**1. Docker no AL2023:** Correto. Usa `dnf install -y docker` (pacote nativo AL2023). Sem `yum`, sem `amazon-linux-extras`, sem repositório externo docker-ce incompatível.

**2. Docker Compose v2 como plugin:** Correto. Binário em `/usr/libexec/docker/cli-plugins/docker-compose`, invocado como `docker compose` (sem hífen). Mas a verificação de versão ocorre antes do daemon iniciar — ver C-01.

**3. Swap 2 GB / persistência:** Swap de 2 GB criado corretamente com `dd` + `mkswap` + `swapon` + entrada no `/etc/fstab`. A persistência após reboot está garantida pelo `/etc/fstab`. 2 GB de swap em 1 GB de RAM é adequado para o workload, mas sem controle de `swappiness` o kernel pode não usá-lo agressivamente — ver M-04. Falta verificação de espaço livre antes do `dd` — ver M-03.

**4. `docker build` e memória:** O build não tem parâmetros `--memory` nem `mem_limit` no Compose. Risco de OOM durante compilação de extensões PHP — ver A-01.

**5. DB_HOST, DB_USER, DB_PASS, DB_NAME — como são passados:** Via `templatefile()` no Terraform, codificados em Base64 (`base64encode(var.db_password)`), decodificados no boot com `base64 -d`. O RDS endpoint vem do output `module.database.db_host` (hostname sem porta). Verificação de readiness com `pg_isready` (30 tentativas × 10 s) antes do `install.php`. Correto — ver B-03.

**6. Ordem de boot:** Swap (1) → dnf update (2) → git/jq (3) → postgresql15 (4) → Docker install (5) → Compose install (6) → Compose version check (7) → systemctl docker (9) → EC2_DNS (10) → clone (11) → .env (13) → RDS wait (14) → docker compose up (15) → Apache wait (16) → install.php (17). **Problema:** Compose version check (7) precede systemctl docker (9) — ver C-01.

**7. Pacotes ausentes no host:** Nenhum pacote ausente para o fluxo atual. PHP/curl/unzip são desnecessários no host porque tudo roda dentro do contêiner — ver B-08.

**8. Cloud-init / falhas silenciosas:** `set -euo pipefail` ativo; `exec >> /var/log/user-data-moodle.log 2>&1` garante logging. O risco é o timeout de duração do boot (ver A-04) e a supressão de erros do `dd` com `status=none` (ver M-03).

**9. Idempotência em reboots:** Reboots simples são seguros — Docker reinicia com `restart: unless-stopped`, contêiner existente é restaurado com `config.php` preservado na camada gravável. O problema é a recriação do contêiner — ver A-02.

**10. IAM necessário:** Apenas `LabInstanceProfile` (LabRole). Nenhuma permissão adicional necessária para o fluxo atual (sem ECR, SSM, Secrets Manager). Ver B-07.

---

## Recomendações Prioritárias

1. **(C-01 — Crítico)** Mover as Etapas 6 e 7 para depois da Etapa 9. Ou substituir a verificação por `/usr/libexec/docker/cli-plugins/docker-compose version --short` sem depender do socket do daemon.

2. **(A-01 — Alto)** Adicionar ao `docker-compose.prod.yml`:
   ```yaml
   services:
     moodle:
       mem_limit: 2g
       memswap_limit: 3g
   ```

3. **(A-02 — Alto)** Persistir `config.php` em um volume nomeado ou bind mount fora do contêiner para sobreviver a `docker compose down`.

4. **(M-04 — Médio)** Adicionar `sysctl -w vm.swappiness=80` antes do `docker compose up -d` para garantir uso ativo do swap durante o build.

5. **(M-03 — Médio)** Adicionar antes do `dd`:
   ```bash
   AVAIL=$(df --output=avail / | tail -1)
   [ "$AVAIL" -lt 2200000 ] && { echo "ERRO: espaço insuficiente para swapfile"; exit 1; }
   ```
