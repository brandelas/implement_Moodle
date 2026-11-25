# Tasks — Módulo Terraform: compute

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/compute`  
**Pré-requisito:** `requirements.md` e `design.md` revisados e aprovados. Módulo `networking` implementado e validado (outputs `public_subnet_ids`, `sg_app_id` disponíveis). Módulo `database` implementado (output `rds_endpoint` disponível).

---

## Sequência de Implementação

As tasks estão ordenadas para minimizar dependências circulares e permitir validação incremental. Tasks 01–03 não dependem de AWS. Tasks 04–07 podem ser validadas sem `terraform apply`. Task 08 é validação local com `pytest` e **não requer credenciais AWS**. Credenciais AWS são necessárias somente na TASK-11, que executa `terraform plan` contra a API da AWS.

---

## Status de execução

Atualizado após a implementação. `[x]` = concluída e conferida no código; `[ ]` = depende de execução ainda não registrada. Validação local registrada em 25/11/2026: `terraform fmt -check -recursive` (exit 0), `terraform validate` na raiz e nos módulos (`Success!`) e `pytest tests -v` (65 passed).

- [x] TASK-01 — `variables.tf`
- [x] TASK-02 — `outputs.tf`
- [x] TASK-03 — `main.tf`: AMI e `aws_key_pair`
- [x] TASK-04 — `user_data.sh`
- [x] TASK-05 — `docker-compose.prod.yml`
- [x] TASK-06 — `aws_instance`
- [x] TASK-07 — Validação local (`fmt -check` e `validate`)
- [x] TASK-08 — Testes estruturais (`pytest`)
- [x] TASK-09 — Integração com a configuração raiz
- [x] TASK-10 — Revisão de segurança
- [ ] TASK-11 — `terraform plan` com credenciais AWS ativas

---

### TASK-01 — Criar `variables.tf`

**Objetivo:** declarar as 12 variáveis de entrada do módulo com tipos, padrões e `sensitive` corretos.

**Conteúdo esperado:** as variáveis definidas em AC-08.1 a AC-08.12 e na Interface do Módulo de `design.md`:

| Variável | Tipo | Padrão | `sensitive` |
|---|---|---|---|
| `project_name` | string | — | não |
| `ec2_instance_type` | string | `"t3.micro"` | não |
| `ec2_public_key` | string | — | não |
| `subnet_id` | string | — | não |
| `sg_app_id` | string | — | não |
| `rds_endpoint` | string | — | não |
| `db_name` | string | `"moodle"` | não |
| `db_username` | string | — | sim |
| `db_password` | string | — | sim |
| `moodle_admin_user` | string | `"admin"` | não |
| `moodle_admin_password` | string | — | sim |
| `moodle_site_name` | string | `"Moodle Challenge"` | não |

**Critério de conclusão:** `variables.tf` declarado; `terraform validate` passa (com `main.tf` e `outputs.tf` vazios, após `terraform init -backend=false` no diretório do módulo).

**Requisitos cobertos:** REQ-08 (AC-08.1 a AC-08.12).  
**Decisões:** D-01 (`t3.micro`, revisado), D-04 (`ec2_public_key` sem `sensitive`).

---

### TASK-02 — Criar `outputs.tf`

**Objetivo:** declarar os dois outputs do módulo.

**Conteúdo esperado:**
- `public_ip` → `aws_instance.main.public_ip`
- `public_dns` → `aws_instance.main.public_dns`
- `instance_id` → `aws_instance.main.id`

**Critério de conclusão:** `outputs.tf` declarado com os dois outputs. As referências a `aws_instance.main` serão resolvidas na TASK-06; `terraform validate` completo do módulo ocorre após TASK-06 estar implementada.

**Requisitos cobertos:** REQ-07 (AC-07.1, AC-07.2).  
**Decisões:** Interface do Módulo em `design.md`.

---

### TASK-03 — Criar `main.tf`: data sources e `aws_key_pair`

**Objetivo:** declarar o bloco `terraform { required_providers }`, os dois data sources e o par de chaves SSH.

**Conteúdo esperado:**
- Bloco `terraform { required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } } }` no topo do `main.tf`.
- `data "aws_ami" "amazon_linux_2023"` com `most_recent = true`, `owners = ["amazon"]`, filtros `name = "al2023-ami-*"` e `architecture = "x86_64"` (D-02).
- ~~`data "aws_iam_instance_profile"` com `name = "LabRole"`~~ — substituído (D-03 revisado): o perfil `LabInstanceProfile` é passado por nome no `aws_instance`.
- `resource "aws_key_pair" "main"` com `public_key = var.ec2_public_key` e tag `Name` (D-04).
- Comentário `# TODO:` obrigatório para satisfazer `test_todo_comments.py` (AC-09.2).

**Critério de conclusão:** `main.tf` criado com required_providers, data sources e key pair; arquivo contém `# TODO:`; nenhum recurso IAM declarado como `resource`. A validação completa com `terraform validate` fica para TASK-07, após `aws_instance.main` existir (TASK-06) — executar `terraform validate` neste ponto produzirá erro de referência em `outputs.tf`.

**Requisitos cobertos:** REQ-02 (AC-02.1 a AC-02.4), REQ-03 (AC-03.1 a AC-03.3), REQ-10 (AC-10.1 a AC-10.3).  
**Decisões:** D-02, D-03, D-04.

---

### TASK-04 — Criar `user_data.sh`

**Objetivo:** criar o script de boot seguindo a sequência de **18 etapas** definida em `design.md` (seção "Sequência de execução do `user_data.sh`").

**Conteúdo esperado (sequência completa — 18 etapas):**

1. `set -euo pipefail`; redirecionar saída para `/var/log/user-data-moodle.log`
2. `dnf update -y`
3. Instalar `git` e `jq`: `dnf install -y git jq`
4. Instalar `postgresql15`; validar `pg_isready` com `command -v`; `exit 1` se ausente (D-08)
5. Instalar Docker via `dnf`; verificar versão >= 24; instalar do repositório oficial se inferior
6. Instalar Docker Compose v2 (dnf ou download do binário oficial)
7. Verificar versão do Docker Compose >= 2.30; `exit 1` se inferior (D-06)
8. Adicionar `ec2-user` ao grupo `docker`; `systemctl enable --now docker`
9. Obter `EC2_DNS` via IMDSv2 com token (D-05, D-08)
10. Clonar repositório em `/opt/moodle`
11. Decodificar credenciais Base64: `DB_PASSWORD`, `DB_USERNAME`, `MOODLE_ADMIN_PASS` (D-07)
12. Gerar `/opt/moodle/docker/.env` com bloco agrupado `echo`/`printf`, `chmod 600` (D-07)
13. Loop `pg_isready` sem `-U`: 30 tentativas, 10 s; `exit 1` se esgotado — confirma disponibilidade do servidor, não autenticação (D-08)
14. Iniciar Moodle: `docker compose -f $COMPOSE_FILE up -d` (D-06)
15. Aguardar Apache em `localhost:80` com `curl`, timeout 120 s
16. Verificar se `config.php` já existe (seleção de caminho)
17. Lógica de dois caminhos (D-08):
    - **Caminho A** (sem `config.php`): (a) permissões temporárias `www-data` em `/var/www/html`; (b) `chmod 770 /var/moodledata` permanente; (c) `install.php --user www-data`; (d) verificar código de saída, `php -l`, `grep hostname RDS`; (e) somente após verificações: reverter `chown root:www-data /var/www/html`, `chmod 755`, `chown root:www-data config.php`, `chmod 640`
    - **Caminho B** (com `config.php`): pular instalador; verificar `php -l` e `grep hostname RDS`
18. Registrar resultado em `/var/log/user-data-moodle.log`; `exit 1` se qualquer verificação falhar

**Variáveis Terraform no template** (`${...}`): `db_password_b64`, `db_username_b64`, `moodle_admin_pass_b64`, `rds_endpoint`, `db_name`, `moodle_admin_user`, `moodle_site_name`.  
**Variáveis Bash escapadas** (`$${...}`): `DB_PASSWORD`, `DB_USERNAME`, `MOODLE_ADMIN_PASS`, `EC2_DNS`, `COMPOSE_FILE`, `TOKEN`, `RETRIES`, `WAIT`, `i`.

**Critério de conclusão:** script criado; contém ao menos um `# TODO:` (AC-09.2); não contém `echo` de credenciais; `shellcheck` não reporta erros críticos (opcional mas recomendado).

**Requisitos cobertos:** REQ-04 (AC-04.1 a AC-04.9), REQ-05 (AC-05.1 a AC-05.4).  
**Decisões:** D-05, D-06, D-07, D-08.

---

### TASK-05 — Criar `docker-compose.prod.yml`

**Objetivo:** criar o arquivo Compose de produção com somente o serviço `moodle`, sem PostgreSQL local.

**Conteúdo esperado (D-06):**

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

**Critério de conclusão:** arquivo criado em `terraform/modules/compute/docker-compose.prod.yml`; contém `format: raw`; contém `# TODO:`; `docker compose -f terraform/modules/compute/docker-compose.prod.yml config --quiet` retorna exit 0.

**Requisitos cobertos:** REQ-04 (AC-04.7, AC-04.8).  
**Decisões:** D-06.

---

### TASK-06 — Adicionar `aws_instance` ao `main.tf`

**Objetivo:** declarar a instância EC2 com todos os atributos obrigatórios e o `templatefile()`.

**Conteúdo esperado:**
- `aws_instance "main"`: AMI do data source, `instance_type = var.ec2_instance_type`, `subnet_id = var.subnet_id`, `vpc_security_group_ids = [var.sg_app_id]`, `key_name = aws_key_pair.main.key_name`, `iam_instance_profile = var.iam_instance_profile_name` (`"LabInstanceProfile"`).
- `metadata_options { http_tokens = "required", http_put_response_hop_limit = 1 }` (D-05).
- `user_data = templatefile("${path.module}/user_data.sh", { db_password_b64 = base64encode(var.db_password), moodle_admin_pass_b64 = base64encode(var.moodle_admin_password), db_username_b64 = base64encode(var.db_username), rds_endpoint = var.rds_endpoint, db_name = var.db_name, moodle_admin_user = var.moodle_admin_user, moodle_site_name = var.moodle_site_name })` (D-07).
- Tags `Name` e `Project`.

**Critério de conclusão:** `terraform validate` passa; nenhum recurso `aws_iam_*` declarado como `resource`; `aws_instance.main.public_dns` referenciável.

**Requisitos cobertos:** REQ-01 (AC-01.1 a AC-01.5), REQ-03 (AC-03.2), REQ-04 (AC-04.9), REQ-05 (AC-05.1).  
**Decisões:** D-01, D-02, D-03, D-05, D-07.

---

### TASK-07 — Validação local (`terraform fmt -check` e `terraform validate`)

**Objetivo:** garantir formatação e ausência de erros de sintaxe antes da validação integrada.

**Passos:**
1. `terraform fmt -check -recursive terraform/` — listar arquivos fora do padrão; corrigir com `terraform fmt -recursive` se necessário.
2. **Opção A — validação isolada do módulo** (enquanto a raiz não o instancia):
   - `cd terraform/modules/compute`
   - `terraform init -backend=false`
   - `terraform validate`
   - Atenção: `.terraform/` e `.terraform.lock.hcl` gerados aqui são artefatos locais do teste isolado; o `.terraform.lock.hcl` da raiz (`terraform/.terraform.lock.hcl`) deve ser versionado — não confundir.
3. **Opção B — validação integrada** (após a raiz instanciar o módulo):
   - `terraform init -backend=false` a partir de `terraform/`
   - `terraform validate` a partir de `terraform/`
   - A Opção B verifica também o encadeamento entre módulos; é obrigatória quando a configuração raiz estiver pronta.

**Critério de conclusão:** `terraform fmt -check` retorna exit 0; `terraform validate` retorna `Success! The configuration is valid.` na opção escolhida.

**Requisitos cobertos:** REQ-09 (AC-09.1, AC-09.2), REQ-10.  
**Decisões:** D-07 (templatefile no módulo).

---

### TASK-08 — Verificar testes estruturais do projeto

**Objetivo:** confirmar que a suíte `pytest` passa com os novos arquivos do módulo `compute`.

**Passos:**
1. `pytest tests/test_terraform_module_structure.py -v` — confirmar que `main.tf`, `variables.tf` e `outputs.tf` são detectados em `terraform/modules/compute/` sem `SKIP`.
2. `pytest tests/test_todo_comments.py -v` — confirmar que `main.tf`, `variables.tf`, `outputs.tf`, `user_data.sh` e `docker-compose.prod.yml` contêm `# TODO:`.
3. `pytest tests/ -v` — confirmar que nenhum outro teste regrediu.

**Critério de conclusão:** todos os testes passam sem `SKIP` nem falha nova.

**Requisitos cobertos:** REQ-09 (AC-09.1, AC-09.2).

---

### TASK-09 — Integrar com a configuração raiz

**Objetivo:** conectar o módulo `compute` à configuração raiz (`terraform/main.tf`) para que a validação integrada (TASK-07, Opção B) funcione e o `terraform plan` possa ser executado.

**Conteúdo esperado em `terraform/main.tf`:**

```hcl
module "compute" {
  source                = "./modules/compute"
  project_name          = var.project_name
  ec2_instance_type     = var.ec2_instance_type
  ec2_public_key        = var.ec2_public_key
  subnet_id             = module.networking.public_subnet_ids[0]
  sg_app_id             = module.networking.sg_app_id
  rds_endpoint          = module.database.db_host
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  moodle_admin_user     = var.moodle_admin_user
  moodle_admin_password = var.moodle_admin_password
  moodle_site_name      = var.moodle_site_name
}
```

**Outputs raiz a expor:** `ec2_public_dns = module.compute.public_dns`, `ec2_public_ip = module.compute.public_ip` e `moodle_url`.

**Critério de conclusão:** `terraform validate` a partir de `terraform/` passa (Opção B da TASK-07); `module.compute.*` referenciável nos outputs da raiz.

**Requisitos cobertos:** REQ-06 (AC-06.1 a AC-06.3), REQ-07 (AC-07.1, AC-07.2).  
**Decisões:** D-07 (normalização do `rds_endpoint` via `split`), D-10.

---

### TASK-10 — Revisão de segurança

**Objetivo:** verificar manualmente os critérios de segurança antes do `terraform apply`.

**Checklist:**

| Item | O que verificar | Referência |
|---|---|---|
| Nenhuma credencial em texto claro nos `.tf` | `git grep -i "password\|secret\|token" terraform/modules/compute/` não retorna valores literais | AC-05.2, REQ-05 |
| `terraform.tfstate` não commitado | `git check-ignore -v terraform/terraform.tfstate` retorna o padrão do `.gitignore` | AC-05.2 |
| `ec2_public_key` sem `sensitive` | Variável declarada sem `sensitive = true` em `variables.tf` | D-04, AC-02.2 |
| `db_password`, `db_username`, `moodle_admin_password` com `sensitive = true` | Verificar declarações em `variables.tf` | AC-05.1, AC-08.8, AC-08.9, AC-08.11 |
| IMDSv2 declarado | `http_tokens = "required"` em `metadata_options` do `aws_instance` | D-05, AC-05.4 |
| Nenhum recurso IAM | `grep -r "aws_iam_role\|aws_iam_instance_profile\|aws_iam_user" terraform/modules/compute/` não retorna `resource` | AC-10.1, REQ-10 |
| `LabInstanceProfile` | `aws_instance.main` usa `iam_instance_profile = var.iam_instance_profile_name` (`"LabInstanceProfile"`); nenhum bloco IAM | AC-03.1, AC-03.2 |
| `user_data.sh` sem `echo` de credenciais | Revisar o script manualmente para confirmar ausência de impressão de valores sensíveis em log | AC-05.3, D-07 |
| Risco de credenciais no state e IMDS documentado | Registrar no `entrega.md` conforme AC-05.3 | REQ-05 |

**Critério de conclusão:** todos os itens do checklist confirmados; pendências documentadas.

---

### TASK-11 — `terraform plan` com credenciais AWS ativas

**Objetivo:** confirmar que o plano de execução é gerado sem erros antes de qualquer provisionamento.

**Pré-requisito:** credenciais do AWS Learn Lab configuradas (`aws sts get-caller-identity` retorna com sucesso); `terraform.tfvars` preenchido com todos os valores obrigatórios (incluindo `ssh_allowed_cidr = "SEU_IP/32"` e credenciais do banco).

**Passos:**
1. `terraform init` a partir de `terraform/`.
2. `terraform plan` a partir de `terraform/` — **sem** a flag `-out`; nenhum arquivo de plano binário deve ser gerado, armazenado, versionado ou compartilhado.
3. Revisar o plano no terminal: confirmar que nenhum recurso existente será destruído acidentalmente; confirmar que os recursos do módulo `compute` aparecem como `+` (criação).
4. Registrar o output textual do plano (captura de tela ou cópia do texto) como evidência para o `entrega.md`.

**Critério de conclusão:** `terraform plan` retorna exit 0 sem erros; plano mostra os recursos esperados (AMI data source, key pair, instância EC2 com `metadata_options`); nenhum arquivo `.tfplan` foi criado.

**Requisitos cobertos:** REQ-01, REQ-02, REQ-03, REQ-06.  
**Atenção:** `terraform apply` e `terraform destroy` **não fazem parte desta tarefa** e exigem autorização explícita separada antes de serem executados.

---

## Rastreabilidade Requirements → Tasks

| Requirement | Tasks principais |
|---|---|
| REQ-01 (EC2 Amazon Linux 2023) | TASK-03, TASK-06 |
| REQ-02 (key pair SSH) | TASK-03, TASK-06 |
| REQ-03 (`LabInstanceProfile`) | TASK-03, TASK-06, TASK-10 |
| REQ-04 (user_data: Docker + Moodle) | TASK-04, TASK-05 |
| REQ-05 (risco de credenciais) | TASK-04, TASK-06, TASK-10 |
| REQ-06 (integração com networking) | TASK-09 |
| REQ-07 (outputs) | TASK-02, TASK-09 |
| REQ-08 (variáveis) | TASK-01 |
| REQ-09 (testes estruturais) | TASK-03, TASK-04, TASK-05, TASK-08 |
| REQ-10 (compatibilidade Learn Lab) | TASK-03, TASK-06, TASK-10 |

## Rastreabilidade Decisões de Design → Tasks

| Decisão | Task |
|---|---|
| D-01 (`t3.micro`) | TASK-01, TASK-06 |
| D-02 (AMI data source) | TASK-03 |
| D-03 (`LabInstanceProfile`) | TASK-03 |
| D-04 (key pair, sem sensitive) | TASK-01, TASK-03 |
| D-05 (IMDSv2) | TASK-06, TASK-10 |
| D-06 (Compose prod, format: raw, versão 2.30) | TASK-04, TASK-05 |
| D-07 (Base64, .env, templatefile no módulo) | TASK-04, TASK-06 |
| D-08 (instalação Moodle, dois caminhos, permissões) | TASK-04 |
| D-09 (persistência, volume moodledata) | TASK-05 |
| D-10 (integração networking, split rds_endpoint) | TASK-09 |
