# Design — Módulo Terraform: compute

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/compute`

---

## Estrutura de Arquivos

```
terraform/modules/compute/
├── main.tf                  # Recursos AWS: data sources, key pair, EC2
├── variables.tf             # Variáveis de entrada com validações e sensitive
├── outputs.tf               # public_ip, public_dns e instance_id
├── user_data.sh             # Script de boot: Docker, Compose, Moodle
└── docker-compose.prod.yml  # Compose de produção: somente serviço moodle
```

Nenhum arquivo adicional é necessário. O módulo não usa `locals.tf` separado.

> **Nota de escopo:** os arquivos da raiz Terraform (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars.example`) não fazem parte desta Spec. São responsabilidade da configuração raiz que instancia os três módulos.

---

## Decisões de Design

### D-01: Tipo de instância EC2 — `t3.micro` *(revisado)*

**Decisão:** `t3.micro` — padrão da variável `ec2_instance_type`, com swap de 2 GB criado no `user_data.sh` e disco raiz de 16 GB.

**Motivo da revisão:** o enunciado oficial da prova exige `t3.micro` no módulo `compute`. Por ser o requisito mais específico, prevalece sobre a rubrica genérica do template. A justificativa original fica registrada abaixo apenas como histórico.

**Motivo original (histórico, superado):** `docs/evaluation-rubric.md`, `docs/architecture.md` e `docs/terraform-guide.md` especificam `t3.medium` de forma consistente. `CHALLENGE.md` não menciona o tipo de instância EC2. Usar `t3.medium` garante aderência à rubrica de avaliação. PC-01 resolvido neste design.

---

### D-02: AMI — data source `aws_ami`

**Decisão:** buscar a AMI do Amazon Linux 2023 via `data "aws_ami"` em vez de fixar um ID.

**Motivo:** IDs de AMI são específicos por região e mudam com as atualizações. O data source garante que sempre se obtenha a versão mais recente disponível na conta, sem necessidade de atualização manual.

**Filtros aplicados:**

```hcl
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
```

---

### D-03: IAM Instance Profile — `LabInstanceProfile` *(revisado)*

**Decisão:** `iam_instance_profile = var.iam_instance_profile_name` (padrão `"LabInstanceProfile"`), sem data source nem recurso IAM. No Learner Lab, `LabRole` é a **role** e `LabInstanceProfile` é o **instance profile** que a contém; o enunciado da prova e a aula 04 usam `iam_instance_profile = "LabInstanceProfile"`. O bloco abaixo, da versão original da Spec, foi substituído.

**Motivo:** o AWS Academy Learner Lab bloqueia a criação de `aws_iam_role`, `aws_iam_instance_profile` e `aws_iam_user` com `AccessDenied`. O `LabRole` pré-existente fornece as permissões necessárias para a EC2 interagir com serviços AWS.

```hcl
data "aws_iam_instance_profile" "lab_role" {
  name = "LabRole"
}
```

---

### D-04: Par de chaves SSH — `aws_key_pair`

**Decisão:** criar `aws_key_pair` com a chave pública fornecida via `var.ec2_public_key`. A chave pública não é dado sensível (é projetada para ser pública); a variável não usa `sensitive = true`.

**Motivo:** a chave privada nunca entra no código ou no repositório — fica apenas no sistema local do aluno. O `.gitignore` cobre `.pem` e `*.key`. A chave pública vai apenas para a API da AWS para permitir autenticação SSH.

---

### D-05: IMDSv2 obrigatório

**Decisão:** configurar `http_tokens = "required"` no recurso `aws_instance` para exigir IMDSv2.

**Motivo:** IMDSv2 exige um token de sessão para acessar `http://169.254.169.254/latest/user-data`, dificultando o acesso por scripts não autorizados sem o token. Isso **não elimina** o risco de exposição de credenciais — quem tem acesso SSH à instância pode obter o token e ler o user data, e as credenciais continuam gravadas no Terraform state em texto claro. A mitigação é parcial e deve ser documentada no `entrega.md`.

```hcl
metadata_options {
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
}
```

---

### D-06: Compose de produção — `docker-compose.prod.yml`

**Decisão:** criar `terraform/modules/compute/docker-compose.prod.yml` com somente o serviço `moodle`, sem o serviço `db`. O arquivo `docker/docker-compose.yml` **não é alterado**.

**Problema de caminhos:** o `docker-compose.prod.yml` fica em `terraform/modules/compute/` no repositório. Após o clone em `/opt/moodle`, o arquivo estará em `/opt/moodle/terraform/modules/compute/docker-compose.prod.yml`. O contexto de build precisa alcançar `docker/Dockerfile`, que estará em `/opt/moodle/docker/Dockerfile`.

**Solução — caminhos relativos ao arquivo Compose:** o Docker Compose resolve `context`, `dockerfile` e `env_file` relativamente ao diretório onde o arquivo Compose está localizado, independentemente de onde o comando `docker compose` é executado. Portanto, o `docker-compose.prod.yml` pode usar caminhos relativos à sua própria localização em `terraform/modules/compute/`:

```yaml
# TODO: Ajustar caminhos e portas conforme o ambiente de produção.
services:
  moodle:
    build:
      context: ../../../docker
      dockerfile: Dockerfile
    env_file:
      - path: ../../../docker/.env
        format: raw
    ports:
      - "80:80"
    restart: unless-stopped
    volumes:
      - moodle_www:/var/moodledata
volumes:
  moodle_www:
```

**Notas sobre esta estrutura:**
- `context: ../../../docker` aponta para `/opt/moodle/docker/`, diretório que contém o `Dockerfile`.
- `env_file.path: ../../../docker/.env` aponta para `/opt/moodle/docker/.env`, gerado pelo `user_data.sh` antes da execução do Compose. `format: raw` impede que o Compose interprete `$` nos valores das credenciais — requer Docker Compose 2.30 ou superior.
- O volume `moodle_data` em `/var/www/html` foi **removido**: montar um volume nomeado sobre `/var/www/html` ocultaria o código do Moodle já instalado pela imagem. O código Moodle permanece na camada da imagem, onde foi colocado pelo `Dockerfile`. Apenas `/var/moodledata` (arquivos de upload e dados de sessão) é persistido em volume.
- **Porta 80** (conforme `docs/architecture.md` — acesso direto pelo DNS público da EC2). PC-02 resolvido neste design.

O `user_data.sh` pode executar o Compose de qualquer diretório usando o caminho absoluto para o arquivo:

```bash
docker compose -f /opt/moodle/terraform/modules/compute/docker-compose.prod.yml up -d
```

---

### D-07: Geração do `.env` e variáveis de ambiente

**Decisão:** o `user_data.sh` gera `/opt/moodle/docker/.env` com permissões restritas (`chmod 600`). As credenciais são passadas via Base64 no template Terraform e decodificadas no boot — evitando que valores com `$`, `!`, `\` ou aspas sejam interpretados indevidamente pelo Bash ou pelo Terraform durante a renderização do template.

**`rds_endpoint` — normalização do hostname:** o output `rds_endpoint` do módulo `database` retorna o endpoint RDS no formato `hostname:5432`. A variável recebida pelo módulo `compute` deve conter **somente o hostname**, sem a porta. A separação é feita na configuração raiz antes de passar ao módulo (ver D-10).

A porta 5432 é declarada separadamente no `.env` como `MOODLE_DATABASE_PORT_NUMBER=5432`.

**Restrição de formato das credenciais:** valores das variáveis `db_password`, `moodle_admin_password` e `db_username` **não podem conter quebras de linha**. Quebras de linha corromperiam o arquivo `.env` e a decodificação Base64. Esta restrição deve ser documentada no `terraform.tfvars.example`.

**Estratégia de passagem segura com Base64:** para evitar que caracteres especiais nas credenciais sejam expandidos pelo Bash ou interpretados pelo `templatefile()`, os valores são codificados em Base64 dentro do próprio módulo `compute` e decodificados no boot. O `templatefile()` fica em `terraform/modules/compute/main.tf`, usando `${path.module}/user_data.sh` para localizar o template:

```hcl
# terraform/modules/compute/main.tf
resource "aws_instance" "main" {
  # ...
  user_data = templatefile("${path.module}/user_data.sh", {
    db_password_b64       = base64encode(var.db_password)
    moodle_admin_pass_b64 = base64encode(var.moodle_admin_password)
    db_username_b64       = base64encode(var.db_username)
    rds_endpoint          = var.rds_endpoint   # já normalizado pela raiz (ver D-10)
    db_name               = var.db_name
    moodle_admin_user     = var.moodle_admin_user
    moodle_site_name      = var.moodle_site_name
  })
}
```

A configuração raiz apenas passa as variáveis ao módulo — não monta o `user_data` diretamente:

```hcl
# terraform/main.tf — configuração raiz
module "compute" {
  source                 = "./modules/compute"
  subnet_id              = module.networking.public_subnet_ids[0]
  sg_app_id              = module.networking.sg_app_id
  rds_endpoint           = module.database.db_host  # revisado: antes split(":", rds_endpoint)[0]
  db_password            = var.db_password
  moodle_admin_password  = var.moodle_admin_password
  db_username            = var.db_username
  db_name                = var.db_name
  moodle_admin_user      = var.moodle_admin_user
  moodle_site_name       = var.moodle_site_name
  # ... demais variáveis
}
```

> **Base64 não é criptografia.** Codificar em Base64 resolve o problema de expansão de caracteres especiais pelo Bash e pelo Terraform, mas **não protege as credenciais contra leitura**. Os valores codificados ficam gravados no Terraform state e no IMDS da instância EC2 exatamente como os valores em texto claro — apenas em formato diferente. Qualquer pessoa com acesso ao state ou ao endpoint IMDS pode decodificá-los trivialmente com `base64 -d`.

No `user_data.sh` (template), os valores Base64 são decodificados antes de qualquer uso, **sem fazer echo para o log**:

```bash
DB_PASSWORD=$(echo "${db_password_b64}" | base64 -d)
DB_USERNAME=$(echo "${db_username_b64}" | base64 -d)
MOODLE_ADMIN_PASS=$(echo "${moodle_admin_pass_b64}" | base64 -d)
```

**Geração do `.env` sem expansão indevida:** o `.env` é escrito usando um bloco agrupado com `echo` e `printf`, redirecionado para o arquivo de destino. `printf "%s\n"` é usado especificamente para senhas, evitando que valores com `\n` ou `-e` sejam mal interpretados por `echo`. O bloco não é um heredoc — o delimitador citado não é usado aqui porque os valores já chegam como variáveis Bash decodificadas do Base64 e não precisam de desabilitação de expansão adicional:

```bash
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
```

> `printf "%s\n"` em vez de `echo` para senhas garante que valores com `\n` ou `-e` não sejam mal interpretados. `${db_name}`, `${rds_endpoint}`, `${moodle_admin_user}` e `${moodle_site_name}` são variáveis Terraform sem caracteres especiais problemáticos; `$${DB_PASSWORD}`, `$${DB_USERNAME}` e `$${MOODLE_ADMIN_PASS}` são variáveis Bash escapadas no template.

**`env_file.format: raw` obrigatório:** o `docker-compose.prod.yml` usa `env_file.format: raw`, disponível no Docker Compose 2.30 ou superior. Isso impede que o Compose interprete `$` nos valores das credenciais:

```yaml
env_file:
  - path: ../../../docker/.env
    format: raw
```

O `user_data.sh` deve verificar a versão do Compose **antes de iniciar qualquer serviço** e interromper a execução com erro explícito se for inferior a 2.30:

```bash
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null | tr -d 'v')
REQUIRED="2.30.0"
if ! printf "%s\n%s\n" "$${REQUIRED}" "$${COMPOSE_VERSION}" | sort -V -C 2>/dev/null; then
  echo "ERRO: Docker Compose $${COMPOSE_VERSION} instalado; versao minima exigida: $${REQUIRED}." \
    >> /var/log/user-data-moodle.log
  exit 1
fi
```

Não existe fallback para versões anteriores a 2.30 — se a versão instalada for inferior, o script falha e o operador deve garantir a versão correta antes de prosseguir.

**Escape de interpolações no `templatefile()`:** qualquer `${VAR}` no template é interpretado pelo Terraform. Para preservar variáveis Bash, use `$${VAR}` no template — renderizado como `${VAR}` no script final. As variáveis Terraform (`${db_name}`, `${rds_endpoint}`, `${moodle_admin_user}`, `${moodle_site_name}`) são substituídas diretamente. Variáveis Bash como `$${DB_PASSWORD}`, `$${TOKEN}` e `$${EC2_DNS}` são escapadas para resolução em tempo de execução.

---

### D-08: Instalação do Moodle — instalador CLI

**Decisão:** usar o instalador CLI oficial do Moodle (`admin/cli/install.php`) dentro do contêiner para concluir a instalação inicial conectando ao RDS.

**Motivo:** o `Dockerfile` existente (`php:8.1-apache`) instala o código do Moodle em `/var/www/html`, mas **não** configura automaticamente o banco de dados nem gera `config.php`. As variáveis `MOODLE_*` no `.env` são usadas pelo `docker-compose.prod.yml` apenas para passar os valores ao contêiner — a interpretação depende do entrypoint da imagem, que neste caso é o Apache padrão e **não executa o instalador automaticamente**.

**Fluxo de instalação no boot:**

1. O Compose sobe o contêiner Moodle (Apache + código PHP).
2. O `user_data.sh` decodifica as credenciais Base64 (ver D-07).
3. Aguarda o RDS com `pg_isready` (sem `-U` — ver espera pelo RDS abaixo).
4. Aguarda o Apache responder em localhost:80 (loop separado com curl).
5. Verifica se `config.php` já existe — se sim, pula a instalação.
6. Se não existir, executa o instalador com `docker compose exec --user www-data`.
7. Valida a instalação em três etapas e registra resultado.

**Proteção contra reinstalação e dois caminhos explícitos:** antes de executar o instalador, o script verifica se já existe um `config.php` válido. Os dois caminhos são mutuamente exclusivos:

```bash
COMPOSE_FILE=/opt/moodle/terraform/modules/compute/docker-compose.prod.yml

if docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    test -f /var/www/html/config.php 2>/dev/null; then

  # ── CAMINHO B: config.php já existe ──────────────────────────────────────
  echo "config.php ja existe. Pulando instalacao." >> /var/log/user-data-moodle.log

  # Verificar sintaxe PHP
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      php -l /var/www/html/config.php > /dev/null 2>&1; then
    echo "ERRO: config.php existente tem sintaxe invalida." \
      >> /var/log/user-data-moodle.log
    exit 1
  fi

  # Confirmar hostname do RDS no config.php
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      grep -q "${rds_endpoint}" /var/www/html/config.php; then
    echo "ERRO: config.php nao contem o hostname do RDS esperado." \
      >> /var/log/user-data-moodle.log
    exit 1
  fi

  echo "Moodle ja configurado — verificacoes OK." >> /var/log/user-data-moodle.log

else

  # ── CAMINHO A: instalação inicial ────────────────────────────────────────

  # Permitir temporariamente que www-data crie config.php em /var/www/html
  # (a propriedade será revertida para root após a instalação bem-sucedida)
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown www-data:www-data /var/www/html
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 755 /var/www/html
  # Garantir que www-data pode escrever no diretório de dados (permanente)
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown www-data:www-data /var/moodledata
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 770 /var/moodledata

  # Executar instalador como www-data
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
    echo "ERRO: install.php saiu com erro." >> /var/log/user-data-moodle.log
    exit 1
  fi

  # Verificar sintaxe PHP do config.php gerado
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      php -l /var/www/html/config.php > /dev/null 2>&1; then
    echo "ERRO: config.php gerado tem sintaxe invalida." \
      >> /var/log/user-data-moodle.log
    exit 1
  fi

  # Confirmar hostname do RDS no config.php gerado
  if ! docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
      grep -q "${rds_endpoint}" /var/www/html/config.php; then
    echo "ERRO: config.php nao contem o hostname do RDS esperado." \
      >> /var/log/user-data-moodle.log
    exit 1
  fi

  # Após instalação bem-sucedida, reverter /var/www/html para root
  # (o código Moodle não deve ser permanentemente gravável por www-data)
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown root:www-data /var/www/html
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 755 /var/www/html
  # Ajustar config.php: root é dono, grupo www-data, Apache lê mas não escreve
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chown root:www-data /var/www/html/config.php
  docker compose -f "$${COMPOSE_FILE}" exec -T moodle \
    chmod 640 /var/www/html/config.php

  echo "Moodle instalado com sucesso." >> /var/log/user-data-moodle.log
fi
```

> `${rds_endpoint}`, `${db_name}`, `${moodle_site_name}` e `${moodle_admin_user}` são variáveis Terraform substituídas pelo `templatefile()`. `$${DB_USERNAME}`, `$${DB_PASSWORD}`, `$${MOODLE_ADMIN_PASS}`, `$${EC2_DNS}` e `$${COMPOSE_FILE}` são variáveis Bash escapadas no template.

**Permissões de `www-data` — ordem das operações (Caminho A):**

1. **Antes do instalador:** `chown www-data:www-data /var/www/html` + `chmod 755` — permite que `www-data` crie `config.php`.
2. **Permanente:** `chown www-data:www-data /var/moodledata` + `chmod 770` — `www-data` precisa de leitura e escrita no diretório de dados durante toda a vida do contêiner.
3. **Após instalação bem-sucedida:** `chown root:www-data /var/www/html` + `chmod 755` — reverte a propriedade do diretório; o código Moodle não fica permanentemente gravável por `www-data`.
4. **`config.php`:** `chown root:www-data` + `chmod 640` — `root` é dono, grupo `www-data` lê (Apache precisa), ninguém além de `root` escreve. A reversão ocorre somente após todas as verificações do Caminho A passarem.

**`wwwroot` — DNS público via IMDSv2 *(PC-03 resolvido)*:** obtido como etapa 9 da sequência, antes de qualquer uso. HTTP na porta 80, sem caminho adicional.

**Comportamento em caso de recriação do contêiner — limitação declarada:**

| Cenário | Resultado |
|---|---|
| `docker compose restart` ou `start` (mesmo contêiner) | Camada gravável preservada; `config.php` mantido |
| `docker compose down` + `up` (contêiner recriado) | `config.php` **perdido**; banco de dados intacto no RDS |
| Recriação do contêiner com banco já inicializado | A proteção impede nova execução do `install.php` **somente se `config.php` ainda existir**. Se o contêiner for recriado (e `config.php` perdido), o instalador será executado novamente. `install.php` **não foi projetado para reexecução idempotente** em banco já inicializado — pode falhar ou produzir estado inconsistente. A recuperação neste cenário requer restauração do `config.php` a partir de backup do arquivo ou do banco. Não execute operações destrutivas no RDS sem backup prévio. |
| Recriação da EC2 (`terraform destroy` + `apply`) | EC2 nova, clone novo, volumes Docker perdidos; banco RDS preservado. Nova instalação necessária com atenção ao banco existente. |

Para o escopo educacional do desafio, o operador deve evitar `docker compose down` em produção. O `user_data.sh` só executa no primeiro boot da EC2.

---

### D-09: Persistência de dados

**Decisão:** usar um único volume Docker nomeado (`moodle_www`) montado em `/var/moodledata` para persistir os arquivos de upload e dados de sessão do Moodle.

**Por que somente `/var/moodledata`:** o volume `moodle_data` em `/var/www/html` foi removido. Montar um volume nomeado sobre `/var/www/html` ocultaria o código do Moodle instalado na imagem pelo `Dockerfile`, que reside exatamente nesse diretório. O código Moodle permanece na camada imutável da imagem Docker; nenhum volume deve ser montado sobre ele.

**O que é persistido e o que não é:**

| Dado | Localização | Persistido em volume? | Sobrevive a `docker compose down`? | Sobrevive à recriação da EC2? |
|---|---|---|---|---|
| Código Moodle | `/var/www/html` (na imagem) | Não (nem deve ser) | Sim (re-pull/build da imagem) | Sim (re-clone e rebuild) |
| `config.php` | `/var/www/html/config.php` (no contêiner) | Não | Não — perdido se o contêiner for recriado | Não |
| Arquivos de upload e cursos | `/var/moodledata` | Sim (`moodle_www`) | Sim | Não (volume local na EC2) |
| Banco de dados | RDS externo | N/A | Sim | Sim |

**Limitação declarada:** a persistência dos dados é local ao disco da EC2. Se a instância for destruída e recriada (`terraform destroy` + `terraform apply`), todos os volumes Docker são perdidos. O RDS preserva o banco de dados entre recriações, mas o `config.php` e os arquivos do moodledata precisarão ser refeitos. Para o escopo educacional do desafio, isso é aceitável.

**Mitigação futura** (fora do escopo do desafio): usar EFS para o moodledata permitiria persistir os arquivos além do ciclo de vida da instância.

---

### D-10: Integração com o módulo networking

O módulo `compute` recebe os IDs de rede via variáveis. Os outputs reais do módulo `networking` são:

| Output do networking | Variável no compute | Uso |
|---|---|---|
| `public_subnet_ids[0]` | `var.subnet_id` | Subnet onde a EC2 é criada |
| `sg_app_id` | `var.sg_app_id` | Security Group associado à EC2 |

O output `sg_db_id` do `networking` é passado ao módulo `database`, não ao `compute`. O módulo `compute` não recebe nem usa `sg_db_id`.

A integração é feita exclusivamente na configuração raiz (`terraform/main.tf`):

```hcl
module "compute" {
  source        = "./modules/compute"
  subnet_id     = module.networking.public_subnet_ids[0]
  sg_app_id     = module.networking.sg_app_id
  rds_endpoint  = module.database.db_host  # revisado: antes split(":", rds_endpoint)[0]
  # ... demais variáveis
}
```

---

## Interface do Módulo

### Inputs (`variables.tf`)

```hcl
variable "project_name"         { type = string }
variable "ec2_instance_type"    { type = string; default = "t3.micro" }
variable "ec2_public_key"       { type = string }                          # sem sensitive
variable "subnet_id"            { type = string }
variable "sg_app_id"            { type = string }
variable "rds_endpoint"         { type = string }
variable "db_name"              { type = string; default = "moodle" }
variable "db_username"          { type = string; sensitive = true }
variable "db_password"          { type = string; sensitive = true }
variable "moodle_admin_user"    { type = string; default = "admin" }
variable "moodle_admin_password"{ type = string; sensitive = true }
variable "moodle_site_name"     { type = string; default = "Moodle Challenge" }
```

### Outputs (`outputs.tf`)

```hcl
output "public_ip"    { value = aws_instance.main.public_ip }
output "public_dns"   { value = aws_instance.main.public_dns }
output "instance_id"  { value = aws_instance.main.id }
```

---

## Sequência de execução do `user_data.sh`

```
1.  set -euo pipefail
    Redirecionar stdout e stderr para /var/log/user-data-moodle.log
2.  Atualizar pacotes (dnf update -y)
3.  Instalar git e jq (dnf install -y git jq)
4.  Instalar cliente PostgreSQL e validar presença de pg_isready:
      dnf install -y postgresql15
      command -v pg_isready || { echo "ERRO: pg_isready nao encontrado"; exit 1; }
5.  Instalar Docker via dnf; verificar versão >= 24
    └─ se < 24: adicionar repositório oficial do Docker para Amazon Linux e reinstalar
6.  Instalar Docker Compose v2 (dnf ou download do binário oficial)
7.  Verificar versão do Docker Compose >= 2.30; exit 1 se inferior
8.  Adicionar ec2-user ao grupo docker
9.  systemctl enable --now docker
10. Obter EC2_DNS via IMDSv2 (antes de qualquer uso do DNS):
      TOKEN=...  (curl com PUT para /latest/api/token)
      EC2_DNS=... (curl com token para /latest/meta-data/public-hostname)
      (no template: $${TOKEN} e $${EC2_DNS} → Terraform renderiza ${TOKEN} e ${EC2_DNS})
11. Clonar repositório em /opt/moodle
12. Decodificar credenciais Base64 (recebidas do templatefile via main.tf do módulo):
      DB_PASSWORD=$(echo "${db_password_b64}" | base64 -d)
      DB_USERNAME=$(echo "${db_username_b64}" | base64 -d)
      MOODLE_ADMIN_PASS=$(echo "${moodle_admin_pass_b64}" | base64 -d)
      ⚠ Base64 não é criptografia — apenas evita expansão de caracteres especiais
13. Gerar /opt/moodle/docker/.env com chmod 600 (ver D-07)
      Usar printf "%s\n" para senhas; sem echo para o log
14. Aguardar RDS com pg_isready -h <hostname> -p 5432 (sem -U):
      30 tentativas, 10s intervalo; exit 1 se esgotado
      pg_isready confirma disponibilidade do servidor; não valida
      credenciais nem acesso ao banco — autenticação real ocorre no install.php
15. Iniciar Moodle:
      COMPOSE_FILE=/opt/moodle/terraform/modules/compute/docker-compose.prod.yml
      docker compose -f "$COMPOSE_FILE" up -d
16. Aguardar Apache responder em localhost:80 (loop com curl, timeout 120s)
17. Executar lógica de dois caminhos (ver D-08):
      Caminho A (sem config.php):
        a) Ajustar permissões temporárias (chown www-data /var/www/html, chmod 755)
        b) Ajustar /var/moodledata (chown www-data, chmod 770) — permanente
        c) Executar install.php como www-data
        d) Verificar código de saída, php -l e grep hostname RDS
        e) Somente após todas as verificações passarem:
             chown root:www-data /var/www/html && chmod 755 /var/www/html
             chown root:www-data /var/www/html/config.php && chmod 640 /var/www/html/config.php
      Caminho B (com config.php): pular instalador, verificar php -l e grep hostname RDS
18. Registrar "Moodle instalado com sucesso" ou "Moodle ja configurado — verificacoes OK"
      (somente após todas as verificações do caminho correspondente)
      Se qualquer verificação falhar → registrar erro específico e exit 1
```

---

## Testabilidade sem AWS

| Verificação | Comando | O que valida |
|---|---|---|
| Estrutura de arquivos | `pytest tests/test_terraform_module_structure.py -v` | `main.tf`, `variables.tf`, `outputs.tf` existem |
| Comentários `# TODO:` | `pytest tests/test_todo_comments.py -v` | Todos os `.tf` e `.sh` têm `# TODO:` |
| Formatação Terraform | `terraform fmt -check -recursive terraform/` | Estilo padronizado |
| Validação sintaxe (módulo isolado) | `cd terraform/modules/compute && terraform init -backend=false && terraform validate` | Erros de referência e tipo |
| Validação integrada (após raiz instanciar) | `cd terraform && terraform init -backend=false && terraform validate` | Encadeamento entre módulos |
| Lint do `user_data.sh` | `shellcheck terraform/modules/compute/user_data.sh` | Erros de shell script (opcional) |
| Validação do Compose de produção | `docker compose -f terraform/modules/compute/docker-compose.prod.yml config --quiet` | Sintaxe YAML válida |

---

## Riscos e limitações

| Risco | Severidade | Mitigação disponível no Learn Lab |
|---|---|---|
| Credenciais do RDS em texto claro no Terraform state | Alto | Nenhuma — não commitar o state (`.gitignore`); documentar no `entrega.md` |
| Credenciais do RDS acessíveis via IMDS | Médio | IMDSv2 (`http_tokens = required`) dificulta, mas não impede quem tem acesso SSH |
| `config.php` perdido em `docker compose down` | Médio | Evitar `docker compose down` em produção; reexecução do instalador em banco já inicializado pode falhar — ver D-08 |
| Reexecução de `install.php` em banco existente não é idempotente | Médio | Limitação declarada — não há solução automática no escopo do desafio |
| Recriação da EC2 perde volumes locais e `config.php` | Médio | Aceitável no escopo educacional; RDS preserva o banco |
| Versão do Docker no repositório `dnf` pode ser < 24 | Baixo | Script verifica versão e instala do repositório oficial se necessário |
| `wwwroot` aponta para o DNS da EC2 original após recriação | Baixo | Resolvido: instalador usa DNS obtido do IMDS em tempo de boot; ao recriar a EC2, nova instalação gera novo `config.php` com o novo DNS |

---

## Pontos de Confirmação Pendentes

Todos os pontos PC-01, PC-02 e PC-03 foram resolvidos neste design:

| # | Questão | Decisão tomada |
|---|---|---|
| PC-01 | Tipo de instância | `t3.micro` — ver D-01 (revisado) |
| PC-02 | Porta HTTP do Moodle na EC2 | Porta 80, conforme `docs/architecture.md` — ver D-06 |
| PC-03 | `wwwroot`: DNS público ou IP? | DNS público da EC2 obtido via IMDSv2 em tempo de boot — ver D-08 |

---

## Revisão pós-implementação (TASK-05, TASK-06 e TASK-09)

Ajustes feitos na implementação após conferir o enunciado oficial da prova (`devops_20262/provas/prova-segundo-bimestre-pratica.md`):

| Item | Spec original | Implementado | Motivo |
|---|---|---|---|
| D-01 — tipo da EC2 | `t3.medium` | `t3.micro` + swap de 2 GB + disco de 16 GB | O enunciado da prova exige `t3.micro` (requisito mais específico). O swap compensa o 1 GB de RAM durante o build da imagem e o `install.php`. |
| D-03 — perfil IAM | `data "aws_iam_instance_profile"` com `name = "LabRole"` | `iam_instance_profile = var.iam_instance_profile_name` (padrão `"LabInstanceProfile"`) | O enunciado da prova exige `LabInstanceProfile`, que é o nome do instance profile no Learner Lab (a role associada se chama `LabRole`). Passar o nome dispensa a leitura IAM `GetInstanceProfile` no plan. Nenhum recurso IAM é criado. |
| Outputs | `ec2_public_dns`, `ec2_instance_id` | `public_ip`, `public_dns`, `instance_id` | Nomes exigidos pelo enunciado da prova; a raiz exporta `ec2_public_dns` (exigido pela rubrica). |
| Endpoint do RDS | `split(":", rds_endpoint)[0]` na raiz | output `db_host` (`aws_db_instance.address`) no módulo database | O enunciado pede host, porta, nome, usuário e senha como outputs do módulo database. |
| Clone do repositório | URL fixa, branch padrão | variáveis `repo_url` e `repo_branch` | Permite subir a EC2 a partir da branch onde a solução foi publicada. |
| `user_data.sh` — Docker | fallback para o repositório `docker-ce` (CentOS) | removido; falha com mensagem clara se Docker < 24 | O repositório CentOS não é compatível com o Amazon Linux 2023; o pacote `docker` do AL2023 já atende à versão 24+. |
| `user_data.sh` — `curl -w` | `"%{http_code}"` | `"%%{http_code}"` | `%{` é diretiva de template no `templatefile()` e quebraria o plan. |
| Disco raiz | não especificado | gp3, 16 GB, criptografado | Criptografia em repouso; 16 GB comportam o sistema, a imagem Docker e o swap. |
| `user_data_replace_on_change` | não especificado | `true` | O cloud-init só executa o user_data no primeiro boot; alterar o script exige recriar a instância. |
