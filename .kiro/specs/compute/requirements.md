# Requirements — Módulo Terraform: compute

**Projeto:** Moodle Docker AWS Challenge  
**Disciplina:** DevOps — ADS UniFAAT 2026.2  
**Módulo:** `terraform/modules/compute`  
**Região:** `us-east-1`  
**Referências:** `CHALLENGE.md`, `docs/architecture.md`, `docs/evaluation-rubric.md`, `docs/aws-learn-lab-setup.md`, `docs/terraform-guide.md`, `docker/.env.example`, `docker/Dockerfile`, `docker/docker-compose.yml`, `terraform/modules/networking/outputs.tf`

---

## Decisões Pendentes de Confirmação

Antes de implementar, as seguintes ambiguidades precisam ser resolvidas:

| # | Questão | Fontes em conflito | Impacto |
|---|---|---|---|
| **DP-01** | Tipo de instância EC2 | `CHALLENGE.md` não especifica o tipo de instância EC2 — a busca textual no arquivo não encontrou nenhuma ocorrência de `t3.micro` nem `t3.medium`. As fontes que especificam `t3.medium` são: `docs/evaluation-rubric.md` (p. 85, critério de avaliação de compute): **`t3.medium`**; `docs/architecture.md` (p. 11, 68, 100, arquitetura de referência): **`t3.medium`**; `docs/terraform-guide.md` (p. 215, 291, exemplo de tfvars): **`t3.medium`**. | **Resolvido (revisão):** o enunciado oficial da prova (`devops_20262/provas/prova-segundo-bimestre-pratica.md`, módulo `compute`) exige `t3.micro`. Por ser o requisito mais específico, prevalece sobre a rubrica genérica do template. Padrão: `t3.micro`, com swap de 2 GB criado no `user_data.sh`. |
| **DP-02** | Detalhes de implementação do `docker-compose.prod.yml` | A decisão de usar um `docker-compose.prod.yml` separado com apenas o serviço `moodle` está definida em AC-04.7. O que ainda precisa ser especificado em `design.md`: (a) caminho exato do arquivo `docker-compose.prod.yml` dentro da instância após o clone; (b) como o contexto de build do Compose alcança `docker/Dockerfile`, considerando que o arquivo Compose estará em `terraform/modules/compute/`; (c) localização e geração do arquivo `.env` em produção; (d) como o `docker compose` será invocado no `user_data.sh`. | Decisão de design a ser documentada em `design.md`. Não é mais uma decisão em aberto — a abordagem está definida. |
| **DP-03** | Sensibilidade de segredos no `user_data.sh` | As credenciais do RDS (usuário, senha, endpoint) precisam ser passadas ao Moodle em tempo de boot. O `user_data.sh` renderizado via `templatefile()` fica gravado em texto claro no Terraform state e é acessível via API de metadados da instância EC2 (`http://169.254.169.254/latest/user-data`). `sensitive = true` nas variáveis **não impede** esse registro. Duas mitigações independentes estão disponíveis no Learn Lab: (a) restringir acesso SSH ao IP do aluno, reduzindo acesso direto ao sistema; (b) habilitar IMDSv2 (`http_tokens = "required"` no recurso `aws_instance`), que exige um token de sessão para acessar os metadados via `curl`, dificultando acesso por scripts não autorizados — mas **não elimina** a exposição no Terraform state nem torna o user data inacessível a quem já tem acesso à instância. | O risco residual deve ser documentado no `entrega.md`. Nenhuma mitigação disponível no Learn Lab elimina completamente a exposição das credenciais. |

---

## Introdução

Este módulo é responsável por provisionar a instância EC2 que executa o Moodle em contêiner Docker. Ele consome outputs do módulo `networking` e, após ser criado, exporta o DNS público da EC2 para ser usado no health check e no `entrega.md`.

O módulo **não** cria recursos de rede (VPC, subnets, SGs) nem recursos de banco de dados (RDS) — esses são responsabilidade dos módulos `networking` e `database`, respectivamente.

Restrições do AWS Academy Learner Lab que moldam este módulo: não é possível criar `aws_iam_role`, `aws_iam_instance_profile` ou `aws_iam_user`. A instância usa o instance profile pré-existente `LabInstanceProfile` (que contém a role `LabRole`), referenciado por nome em `iam_instance_profile`, conforme o enunciado da prova.

---

## Requirements

### REQ-01 — Instância EC2 com Amazon Linux 2023

**User Story:** como aluno, quero uma instância EC2 com Amazon Linux 2023 rodando na subnet pública para hospedar o Moodle acessível pela internet.

**Acceptance Criteria:**

- AC-01.1: deve existir um recurso `aws_instance` na subnet pública fornecida por `var.subnet_id`.
- AC-01.2: a AMI deve ser Amazon Linux 2023, obtida via data source `aws_ami` filtrado por `name = "al2023-ami-*"` e `architecture = "x86_64"`, com `most_recent = true`.
- AC-01.3: o tipo da instância deve ser configurado pela variável `var.ec2_instance_type`, com padrão `"t3.micro"` — ver DP-01 para a verificação das fontes.
- AC-01.4: a instância deve ser associada ao Security Group da EC2 fornecido por `var.sg_app_id` (output `sg_app_id` do módulo `networking`).
- AC-01.5: a instância deve receber uma tag `Name` com o valor `"${var.project_name}-ec2"` e uma tag `Project` com o valor `var.project_name`.

---

### REQ-02 — Par de chaves SSH

**User Story:** como aluno, quero um par de chaves SSH associado à EC2 para poder acessar a instância remotamente via terminal, sem armazenar a chave privada no repositório.

**Acceptance Criteria:**

- AC-02.1: deve existir um recurso `aws_key_pair` criado com o conteúdo da variável `var.ec2_public_key`.
- AC-02.2: a chave privada correspondente **nunca** deve ser declarada em nenhum arquivo do módulo nem versionada no repositório (`.gitignore` já cobre `.pem` e `*.key`). Apenas a chave pública (formato OpenSSH, `ssh-rsa AAAA...`) é passada como variável — chave pública não é dado sensível.
- AC-02.3: a instância EC2 deve referenciar esse key pair via `key_name = aws_key_pair.main.key_name`.
- AC-02.4: o recurso `aws_key_pair` deve receber uma tag `Name` com o valor `"${var.project_name}-key"`.

---

### REQ-03 — IAM Instance Profile pré-existente (`LabInstanceProfile`)

**User Story:** como aluno usando o Learn Lab, quero que a EC2 use o instance profile pré-existente `LabInstanceProfile` (role `LabRole`) para que a instância possa interagir com serviços AWS sem que eu precise criar recursos IAM (bloqueados no Learn Lab).

**Acceptance Criteria:**

- AC-03.1: a variável `iam_instance_profile_name` (padrão `"LabInstanceProfile"`) define o instance profile; `LabRole` é o nome da role contida nele e não é usado como nome de instance profile.
- AC-03.2: o `iam_instance_profile` da instância EC2 deve ser `var.iam_instance_profile_name` (o enunciado da prova exige `iam_instance_profile = "LabInstanceProfile"`).
- AC-03.3: o módulo **não** deve declarar nenhum recurso `aws_iam_role`, `aws_iam_policy`, `aws_iam_user` ou `aws_iam_instance_profile` (bloqueados no Learn Lab com `AccessDenied`).

---

### REQ-04 — User data: instalação do Docker e do Moodle

**User Story:** como aluno, quero que a EC2 instale automaticamente o Docker e suba o Moodle no primeiro boot, sem intervenção manual após o `terraform apply`.

**Acceptance Criteria:**

- AC-04.1: deve existir um arquivo `terraform/modules/compute/user_data.sh` com shebang `#!/bin/bash` e `set -euo pipefail`.
- AC-04.2: o script deve instalar o Docker Engine usando o gerenciador de pacotes `dnf` do Amazon Linux 2023 (`dnf install -y docker`). Após a instalação, deve verificar que a versão instalada é 24 ou superior executando `docker --version` e validando o número de versão. Se a versão disponível no repositório `dnf` padrão for inferior a 24, o script deve instalar a partir do repositório oficial do Docker para Amazon Linux.
- AC-04.3: o script deve instalar o Docker Compose v2 como plugin Docker (via `dnf` ou download direto do binário oficial em `https://github.com/docker/compose/releases`).
- AC-04.4: o script deve habilitar e iniciar o serviço Docker (`systemctl enable --now docker`).
- AC-04.5: o script deve clonar o repositório `https://github.com/brandelas/implement_Moodle.git` em `/opt/moodle` (repositório público, sem token).
- AC-04.6: o script deve criar o arquivo `.env` com as variáveis de conexão ao RDS e de configuração do Moodle, injetadas via `templatefile()`. As variáveis devem incluir, no mínimo: `MOODLE_DATABASE_HOST`, `MOODLE_DATABASE_PORT_NUMBER`, `MOODLE_DATABASE_NAME`, `MOODLE_DATABASE_USER`, `MOODLE_DATABASE_PASSWORD`, `MOODLE_USERNAME`, `MOODLE_PASSWORD` e `MOODLE_SITE_NAME` — correspondentes às declaradas em `docker/.env.example`.
- AC-04.6a: **não presumir** que a imagem Docker atual (`php:8.1-apache` com instalação manual do Moodle via `Dockerfile`) interpreta automaticamente as variáveis `MOODLE_*` do arquivo `.env`. O `Dockerfile` existente apenas instala o código do Moodle; a configuração inicial do banco e do administrador depende do instalador do Moodle. A implementação deve garantir que o Moodle complete a instalação inicial conectando ao RDS, usando o instalador CLI oficial (`admin/cli/install.php`) ou gerando `config.php` com os parâmetros corretos. O design em `design.md` deve detalhar a abordagem escolhida.
- AC-04.7: deve existir um arquivo `terraform/modules/compute/docker-compose.prod.yml` contendo **somente** o serviço `moodle`, sem o serviço `db` (PostgreSQL local). O arquivo `docker/docker-compose.yml` existente **não deve ser alterado** — ele permanece para uso no ambiente de desenvolvimento local. O `user_data.sh` deve efetivamente executar `docker compose` usando este Compose de produção para iniciar o Moodle na EC2 após o boot. O `design.md` deve especificar os caminhos corretos: (a) localização do `docker-compose.prod.yml` dentro da instância após o clone; (b) como o contexto de build (`context`) alcança `docker/Dockerfile` a partir do arquivo Compose em `terraform/modules/compute/`; (c) localização e geração do arquivo `.env` em relação ao Compose de produção; (d) forma exata de invocação do `docker compose` no script.
- AC-04.8: o script `user_data.sh` e o arquivo `docker-compose.prod.yml` devem conter pelo menos um comentário `# TODO:` cada, para satisfazer o teste `test_todo_comments.py`.
- AC-04.9: o `user_data.sh` deve ser injetado na instância EC2 via `templatefile("${path.module}/user_data.sh", { ... })`, passando as variáveis de conexão ao RDS e as variáveis do administrador Moodle.

---

### REQ-05 — Risco de segredos no user data e no Terraform state

**User Story:** como aluno, quero estar ciente dos riscos de segurança associados à passagem de credenciais via `user_data.sh`, para documentá-los no relatório e aplicar mitigações disponíveis no Learn Lab.

**Acceptance Criteria:**

- AC-05.1: as variáveis `db_password` e `db_username` devem ser declaradas com `sensitive = true` no `variables.tf` do módulo. Isso evita que apareçam em texto claro no output do `terraform plan` e `terraform apply`, mas **não** impede o registro no `terraform.tfstate`.
- AC-05.2: o `terraform.tfstate` **nunca** deve ser commitado no repositório — o `.gitignore` já cobre esse padrão. Isso deve ser verificado antes do `git add`.
- AC-05.3: o conteúdo do `user_data.sh` renderizado (com as credenciais substituídas) fica registrado no Terraform state em texto claro e acessível via API de metadados da instância EC2 (`http://169.254.169.254/latest/user-data`). Este risco deve ser documentado no `entrega.md` como parte do relatório de uso de IA e de boas práticas de segurança.
- AC-05.4: duas mitigações independentes estão disponíveis no Learn Lab e devem ser consideradas na implementação:
  - **Restrição de SSH:** o acesso SSH à EC2 é restrito ao IP do aluno via `var.ssh_allowed_cidr`, já implementado no `sg-app` do módulo `networking`. Isso limita quem pode acessar o sistema operacional diretamente, mas não restringe o endpoint IMDS.
  - **IMDSv2 (`http_tokens = "required"`):** habilitar IMDSv2 no recurso `aws_instance` exige um token de sessão para qualquer requisição ao endpoint `http://169.254.169.254/latest/user-data`, dificultando o acesso por scripts de servidor sem a chamada prévia de obtenção do token. No entanto, IMDSv2 **não elimina** a exposição: quem já tem acesso ao sistema (via SSH, por exemplo) ainda pode obter o token e ler o user data. O risco residual no Terraform state também permanece independente desta configuração.

---

### REQ-06 — Integração com o módulo networking

**User Story:** como aluno, quero que o módulo `compute` receba os IDs de rede via variáveis para ser desacoplado do módulo `networking` e poder ser testado ou substituído independentemente.

**Acceptance Criteria:**

- AC-06.1: a variável `var.subnet_id` recebe o ID de uma subnet pública — correspondente a `module.networking.public_subnet_ids[0]` na configuração raiz.
- AC-06.2: a variável `var.sg_app_id` recebe o ID do Security Group da EC2 — correspondente a `module.networking.sg_app_id` na configuração raiz.
- AC-06.3: o módulo `compute` **não** importa, chama nem modifica nenhum recurso do módulo `networking` diretamente. A integração é feita exclusivamente pela configuração raiz (`terraform/main.tf`).

---

### REQ-07 — Outputs do módulo

**User Story:** como aluno, quero que o módulo exporte o IP público, o DNS público e o ID da instância EC2 (o enunciado exige `public_ip` e `public_dns`) para que a configuração raiz possa expô-los como outputs finais e o health check possa ser executado.

**Acceptance Criteria:**

- AC-07.1: output `public_ip` — valor de `aws_instance.main.public_ip`.
- AC-07.2: output `public_dns` — valor de `aws_instance.main.public_dns` (a raiz o expõe como `ec2_public_dns`).
- AC-07.3: output `instance_id` — valor de `aws_instance.main.id`.

---

### REQ-08 — Variáveis do módulo

**User Story:** como aluno, quero que todas as configurações sejam recebidas via variáveis para que o módulo seja reutilizável e os valores sensíveis nunca sejam codificados diretamente.

**Acceptance Criteria:**

- AC-08.1: variável `project_name` (string, sem padrão) — prefixo para nomes e tags.
- AC-08.2: variável `ec2_instance_type` (string, padrão `"t3.micro"`) — tipo da instância EC2 (ver DP-01).
- AC-08.3: variável `ec2_public_key` (string, sem padrão) — conteúdo da chave pública OpenSSH para o `aws_key_pair` (ex.: `ssh-rsa AAAA...`). Chave pública não é dado sensível; não usa `sensitive = true`. A chave privada nunca deve ser declarada como variável nem versionada.
- AC-08.4: variável `subnet_id` (string, sem padrão) — ID da subnet pública onde a EC2 será criada.
- AC-08.5: variável `sg_app_id` (string, sem padrão) — ID do Security Group da EC2 (`sg-app`).
- AC-08.6: variável `rds_endpoint` (string, sem padrão) — endpoint do RDS, injetado no `user_data.sh`.
- AC-08.7: variável `db_name` (string, padrão `"moodle"`) — nome do banco de dados.
- AC-08.8: variável `db_username` (string, sem padrão, `sensitive = true`) — usuário do banco.
- AC-08.9: variável `db_password` (string, sem padrão, `sensitive = true`) — senha do banco. Não deve ter valor padrão — ver AC-05.1.
- AC-08.10: variável `moodle_admin_user` (string, padrão `"admin"`) — usuário administrador do Moodle.
- AC-08.11: variável `moodle_admin_password` (string, sem padrão, `sensitive = true`) — senha do administrador do Moodle.
- AC-08.12: variável `moodle_site_name` (string, padrão `"Moodle Challenge"`) — nome exibido no site Moodle.

---

### REQ-09 — Conformidade com testes existentes

**User Story:** como aluno, quero que os arquivos do módulo `compute` passem nos testes estruturais do repositório para que a suíte `pytest` não regrid.

**Acceptance Criteria:**

- AC-09.1: os três arquivos `main.tf`, `variables.tf` e `outputs.tf` devem existir em `terraform/modules/compute/` — verificado por `test_terraform_module_structure.py`.
- AC-09.2: cada arquivo `.tf` e o `user_data.sh` em `terraform/` deve conter pelo menos um comentário `# TODO:` — verificado por `test_todo_comments.py`.

---

### REQ-10 — Compatibilidade com AWS Academy Learner Lab

**User Story:** como aluno usando o Learn Lab, quero que o módulo não declare recursos bloqueados pelo ambiente para evitar erros de `AccessDenied` no `terraform apply`.

**Acceptance Criteria:**

- AC-10.1: o módulo **não** deve declarar `aws_iam_role`, `aws_iam_policy`, `aws_iam_user` ou `aws_iam_instance_profile` como recursos (`resource`).
- AC-10.2: o módulo **não** deve declarar `aws_route53_*`, `aws_acm_*` ou `aws_cloudfront_*`.
- AC-10.3: as credenciais AWS (access key, secret key, session token) são responsabilidade do provider AWS na configuração raiz e do ambiente de execução — não são declaradas no módulo.
