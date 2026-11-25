# Moodle Docker AWS Challenge

Este repositório é um **template educacional** para um desafio que combina containerização com Docker, infraestrutura como código com Terraform e deploy na nuvem AWS usando o ambiente AWS Learn Lab. O template entrega um ambiente Docker local de referência rodando Moodle 4.x com PostgreSQL 15, além do scaffolding de arquivos, documentação, pipelines de CI/CD e scripts de validação. Os módulos Terraform funcionais e o desenho técnico de arquitetura são **entregas obrigatórias do aluno**.

→ **[Leia o desafio completo](CHALLENGE.md)**


## ✅ Solução implementada — Eloísa Brandão (RA 2325096)

Este fork implementa a infraestrutura AWS do desafio. Resumo do que foi entregue:

| Item | Onde |
|---|---|
| Terraform raiz (integra os 3 módulos) | [`terraform/`](terraform/) |
| Módulo de rede: VPC, 2 subnets públicas + 2 privadas, IGW, route table, `sg-app`/`sg-db` | [`terraform/modules/networking`](terraform/modules/networking) |
| Módulo de computação: EC2 `t3.micro` AL2023, `LabInstanceProfile`, IMDSv2, swap de 2 GB, `user_data.sh` | [`terraform/modules/compute`](terraform/modules/compute) |
| Módulo de banco: RDS PostgreSQL 15 `db.t3.micro`, privado, subnet group em 2 AZs | [`terraform/modules/database`](terraform/modules/database) |
| Documento de arquitetura | [`docs/architecture-design.md`](docs/architecture-design.md) |
| Workflow de plan (PR com comentário + manual) | [`.github/workflows/terraform-plan.yml`](.github/workflows/terraform-plan.yml) |
| Specs do Kiro (requirements, design, tasks) | [`.kiro/specs/`](.kiro/specs/) |
| Evidências (prints) | [`screenshots/`](screenshots/) |

### Pré-requisitos

Docker Engine 24+ com Compose v2, Terraform 1.5+, AWS CLI 2.x, Git, Python 3.8+ e uma sessão ativa do AWS Academy Learner Lab.

### 1. Ambiente local (Windows PowerShell)

```powershell
cd docker
Copy-Item .env.example .env        # edite as senhas no .env (nunca commite este arquivo)
docker compose up -d
docker compose ps                  # db: healthy | moodle: running
# Abra http://localhost:8080
```

### 2. Infraestrutura na AWS

```powershell
# Credenciais temporárias do Learner Lab ("AWS Details" → AWS CLI) em ~/.aws/credentials
aws sts get-caller-identity

# Chave SSH (somente a pública vai para o Terraform)
ssh-keygen -t ed25519 -f $HOME\.ssh\moodle-key

cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # preencha IP /32, chave pública e senhas
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan              # cria recursos com custo — revise o plan antes
```

> A EC2 clona este repositório no boot (variáveis `repo_url`/`repo_branch`). O código precisa estar publicado no GitHub, na branch informada, **antes** do `apply`.

### 3. URL pública do Moodle

```powershell
terraform output moodle_url         # http://ec2-X-X-X-X.compute-1.amazonaws.com
```

O primeiro boot leva cerca de 15 a 25 minutos numa `t3.micro` (instalação do Docker, build da imagem e `install.php`). Para acompanhar: `ssh -i $HOME\.ssh\moodle-key ec2-user@<DNS>` e depois `sudo tail -f /var/log/user-data-moodle.log`. Para validar: `./scripts/health-check.sh http://<DNS>` ou o workflow **Moodle Health Check**.

### 4. Destruir ao final

```powershell
terraform destroy
```

### Testes

```powershell
pip install pytest hypothesis pyyaml
pytest tests/ -v
```

---

## Pré-requisitos (template original)

Antes de começar, verifique se você tem as seguintes ferramentas instaladas e configuradas:

| Ferramenta | Versão mínima | Observação |
|---|---|---|
| [Docker Engine](https://docs.docker.com/get-docker/) | 24.x | Inclui o Docker Compose v2 (`docker compose`) |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5+ | Provider AWS `~> 5.0` |
| [AWS CLI](https://aws.amazon.com/cli/) | 2.x | Para configurar as credenciais do Learn Lab |
| [Git](https://git-scm.com/) | 2.x | Para clonar/forkar o template |
| [Python](https://www.python.org/) | 3.8+ | Para rodar os testes (`pytest` + `hypothesis`) |
| Conta AWS Learn Lab | — | Credenciais temporárias obtidas no portal AWS Academy |

> O ambiente **AWS Learn Lab** fornece credenciais temporárias com permissões restritas (sem IAM, Route 53, ACM ou CloudFront). Consulte [`docs/aws-learn-lab-setup.md`](docs/aws-learn-lab-setup.md) para configurá-las.



## Estrutura do Repositório

```
.
├── .github/
│   └── workflows/                       # Pipelines de CI/CD (GitHub Actions)
│       ├── docker-lint.yml              #   - Lint do Dockerfile (hadolint)
│       ├── health-check.yml             #   - Health check manual (workflow_dispatch)
│       ├── terraform-plan.yml           #   - terraform plan em PR (comenta o plano) e manual
│       └── terraform-validate.yml       #   - fmt-check + validate
├── docker/                              # Ambiente Docker local de referência (funcional)
│   ├── .env.example                     #   - Variáveis de ambiente documentadas
│   ├── Dockerfile                       #   - Imagem Moodle customizada (extensões PHP)
│   └── docker-compose.yml               #   - Orquestra Moodle + PostgreSQL 15
├── docs/                                # Documentação do desafio
│   ├── architecture-design-template.md  #   - Template do desenho técnico (entrega do aluno)
│   ├── architecture.md                  #   - Arquitetura de referência (gabarito)
│   ├── aws-learn-lab-setup.md           #   - Credenciais e limitações do Learn Lab
│   ├── evaluation-rubric.md             #   - Rubrica de avaliação
│   ├── img/                             #   - Imagens usadas na documentação
│   ├── security-practices.md            #   - Boas práticas de segurança
│   ├── terraform-guide.md               #   - Guia dos comandos Terraform
│   └── troubleshooting.md              #   - Problemas comuns e soluções
├── scripts/
│   └── health-check.sh                  # Verificação automatizada do Moodle
├── terraform/                           # Infraestrutura AWS (implementada neste fork)
│   ├── versions.tf / main.tf / variables.tf / outputs.tf  # Raiz que integra os módulos
│   ├── terraform.tfvars.example         #   - Modelo de variáveis (sem segredos)
│   └── modules/
│       ├── networking/                  #   - VPC, subnets, IGW, route table, sg-app, sg-db
│       ├── compute/                     #   - EC2, user_data.sh, docker-compose.prod.yml
│       └── database/                    #   - RDS PostgreSQL 15 privado
├── .kiro/specs/                         # Specs do Kiro (networking, compute, database)
├── .agents/tasks/                       # Relatório do Kiro Workflow investigate
├── screenshots/                         # Evidências da prova
├── tests/                               # Testes de propriedade (pytest + Hypothesis)
│   ├── conftest.py                      #   - Fixtures compartilhadas (repo_root)
│   ├── test_architecture_template_sections.py
│   ├── test_compose_no_hardcoded_creds.py
│   ├── test_dockerfile_extensions.py
│   ├── test_docs_exist.py
│   ├── test_gitignore_patterns.py
│   ├── test_health_check.py
│   ├── test_terraform_module_structure.py
│   ├── test_todo_comments.py
│   └── test_workflow_step_comments.py
├── .gitignore                           # Padrões de segurança (secrets, estado, etc.)
├── CHALLENGE.md                         # Objetivos, entregas e critérios do desafio
├── LICENSE                              # Licença do projeto
├── pyproject.toml                       # Configuração do projeto e dependências de teste
└── README.md                            # Este arquivo (ponto de entrada)
```

> **Nota:** o diretório `terraform/` não fazia parte do template original; ele foi criado neste fork como parte do desafio, instanciando os módulos `networking`, `compute` e `database`. Veja a seção [Infraestrutura AWS com Terraform](#infraestrutura-aws-com-terraform) e o [`CHALLENGE.md`](CHALLENGE.md).



## Ambiente Docker Local

O template entrega um stack Docker funcional para você validar o Moodle localmente antes do deploy na AWS.

```bash
# 1. Entre no diretório docker/
cd docker

# 2. Copie o arquivo de exemplo e preencha as senhas
cp .env.example .env
#    Edite .env e substitua os valores de exemplo (POSTGRES_PASSWORD, MOODLE_PASSWORD, etc.)

# 3. Suba os contêineres (Moodle + PostgreSQL)
docker compose up -d

# 4. Acesse o Moodle no navegador
#    → http://localhost:8080
```

Comandos úteis para gerenciar o ambiente:

```bash
docker compose ps              # Verifica o status dos contêineres
docker compose logs -f moodle  # Acompanha os logs do Moodle
docker compose down            # Para e remove os contêineres
docker compose down -v         # Para e remove os contêineres E os volumes (apaga os dados)
```

O `docker-compose.yml` mapeia a porta `8080` do host para a porta `80` do contêiner Moodle e garante que o Moodle só inicia após o PostgreSQL estar saudável (`depends_on: condition: service_healthy`). Os dados são persistidos em volumes nomeados (`db_data`, `moodle_data`, `moodle_www`).

### Health Check

Após subir o ambiente (local ou na AWS), valide se o Moodle está respondendo corretamente:

```bash
./scripts/health-check.sh http://localhost:8080
# Para a instância EC2 na AWS, use o DNS público:
# ./scripts/health-check.sh http://ec2-XX-XX-XX-XX.compute-1.amazonaws.com
```

O script realiza **3 verificações** em sequência, com até 3 tentativas (intervalo de 30s):

| Verificação | O que testa |
|---|---|
| (a) | HTTP 200 na URL raiz |
| (b) | HTTP 200 em `/login/index.php` |
| (c) | Presença da string `Moodle` no corpo da resposta |

**Interpretando a saída:**

- **`exit 0`** com `[✓]`: Moodle saudável — as 3 verificações passaram.
- **`exit 1`** com `[✗]` + diagnóstico: falhou após 3 tentativas. O script indica qual verificação específica falhou (`raiz`, `login` ou `conteudo`) e sugere comandos de troubleshooting (`docker compose logs`, `curl`, etc.).



## Infraestrutura AWS com Terraform

Os 3 módulos foram implementados neste fork em `terraform/modules/` e são integrados por `terraform/main.tf`:

| Módulo | Recursos a provisionar |
|---|---|
| **`networking`** | VPC `10.0.0.0/16`, 2 subnets públicas + 2 privadas (us-east-1a/1b), Internet Gateway, route table pública, `sg-app` (80 público; 22 só do IP `/32`) e `sg-db` (5432 somente a partir do `sg-app`) |
| **`compute`** | EC2 `t3.micro` (Amazon Linux 2023) com `iam_instance_profile = "LabInstanceProfile"` (sem criar IAM), IMDSv2, `aws_key_pair` e `user_data.sh` via `templatefile()` + `docker-compose.prod.yml` |
| **`database`** | `aws_db_subnet_group` (2 AZs privadas), `aws_db_instance` PostgreSQL 15 classe `db.t3.micro`, 20 GB, `publicly_accessible = false`; outputs de host, porta, nome, usuário e senha (sensíveis) |

Restrições importantes do AWS Learn Lab: não use `aws_route53_*`, `aws_acm_*`, `aws_cloudfront_*` nem `aws_iam_user`. O DNS público do EC2 substitui o Route 53. Veja os detalhes em [`docs/aws-learn-lab-setup.md`](docs/aws-learn-lab-setup.md).

Para a sequência completa de comandos (`init`, `plan`, `apply`, `destroy`) e exemplos de saída esperada, consulte o **[Guia do Terraform](docs/terraform-guide.md)**.



## CI/CD

O repositório inclui pipelines de GitHub Actions em `.github/workflows/`:

| Workflow | Gatilho | O que faz |
|---|---|---|
| [`terraform-validate.yml`](.github/workflows/terraform-validate.yml) | `push` / `pull_request` em `main` | Executa `terraform fmt -check` e `terraform validate` (falha listando arquivos com problemas de formatação) |
| [`docker-lint.yml`](.github/workflows/docker-lint.yml) | `push` / `pull_request` em `main` | Executa `hadolint` no `docker/Dockerfile` |
| [`terraform-plan.yml`](.github/workflows/terraform-plan.yml) | `pull_request` em `main` + `workflow_dispatch` | **Implementado:** `init`, `validate` e `plan` com credenciais temporárias (`AWS_SESSION_TOKEN`); publica o plano como comentário na PR e falha se o plan falhar. Secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `TF_SSH_ALLOWED_CIDR`, `TF_EC2_PUBLIC_KEY`, `TF_DB_USERNAME`, `TF_DB_PASSWORD`, `TF_MOODLE_ADMIN_PASSWORD` |
| [`health-check.yml`](.github/workflows/health-check.yml) | `workflow_dispatch` (input `moodle_url`) | Torna `health-check.sh` executável e o roda contra a URL informada |

> Cada step dos workflows contém um comentário explicativo descrevendo o que a etapa faz.



## Documentação

Toda a documentação de apoio está em `docs/`:

| Documento | Descrição |
|---|---|
| [`docs/architecture-design-template.md`](docs/architecture-design-template.md) | Template para você preencher e entregar como `docs/architecture-design.md` (entrega obrigatória) |
| [`docs/architecture.md`](docs/architecture.md) | Arquitetura de referência da solução AWS (gabarito para professores/monitores) |
| [`docs/aws-learn-lab-setup.md`](docs/aws-learn-lab-setup.md) | Como obter credenciais temporárias do AWS Academy e as limitações do Learn Lab |
| [`docs/terraform-guide.md`](docs/terraform-guide.md) | Guia de referência dos comandos Terraform (`init`, `plan`, `apply`, `destroy`) |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Problemas comuns (porta 8080, healthcheck do DB, credenciais expiradas, etc.) e soluções |
| [`docs/evaluation-rubric.md`](docs/evaluation-rubric.md) | Rubrica de avaliação com critérios e pontuações |
| [`docs/security-practices.md`](docs/security-practices.md) | Boas práticas de segurança (secrets, least privilege, estado do Terraform) |



## Testes

Os testes validam a estrutura e configuração do repositório usando **pytest** + **[Hypothesis](https://hypothesis.readthedocs.io/)** (property-based testing, 100 iterações por propriedade). Eles inspecionam o sistema de arquivos e **não** requerem infraestrutura AWS.

```bash
# Instale as dependências (se ainda não tiver)
pip install pytest hypothesis pyyaml

# Rode todos os testes a partir da raiz do repositório
pytest tests/ -v
```

Os testes cobrem, entre outros: extensões PHP obrigatórias no Dockerfile, ausência de credenciais literais no `docker-compose.yml`, padrões do `.gitignore`, estrutura dos módulos Terraform, comentários `# TODO:` nos arquivos de configuração, comentários nos steps dos workflows, seções do template de arquitetura e o comportamento do `health-check.sh`.



## Avaliação

A avaliação do desafio segue a rubrica detalhada em [`docs/evaluation-rubric.md`](docs/evaluation-rubric.md), que pontua infraestrutura provisionada, Moodle acessível, segurança, documentação e o desenho técnico de arquitetura.

> **Critério eliminatório:** a ausência do arquivo `docs/architecture-design.md` (gerado por você a partir de [`docs/architecture-design-template.md`](docs/architecture-design-template.md)) resulta em desclassificação automática, independentemente da pontuação nas demais categorias.
