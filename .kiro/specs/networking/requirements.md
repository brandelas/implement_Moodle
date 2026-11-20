# Requirements — Módulo Terraform: networking

**Projeto:** Moodle Docker AWS Challenge  
**Disciplina:** DevOps — ADS UniFAAT 2026.2  
**Módulo:** `terraform/modules/networking`  
**Região:** `us-east-1`  
**Referências:** `CHALLENGE.md`, `docs/architecture.md`, `docs/architecture-design.md`, `docs/aws-learn-lab-setup.md`

---

## Introdução

Este módulo é responsável por toda a camada de rede da solução Moodle na AWS. Ele provisiona a VPC, subnets, Internet Gateway, Route Tables e Security Groups que serão consumidos pelos módulos `compute` e `database`. Nenhuma instância EC2 ou RDS é criada aqui.

O módulo deve ser compatível com o AWS Academy Learner Lab: não pode criar recursos IAM (roles, users, groups, instance profiles) e não deve referenciar Route 53, ACM ou CloudFront.

---

## Requirements

### REQ-01 — VPC principal

**User Story:** como aluno provisionando infraestrutura no Learn Lab, quero uma VPC isolada para hospedar todos os recursos do Moodle, de modo que o ambiente de estudo não interfira em outros recursos da conta.

**Acceptance Criteria:**

- AC-01.1: deve existir um recurso `aws_vpc` com CIDR `10.0.0.0/16`.
- AC-01.2: `enable_dns_hostnames` deve ser `true` para que a EC2 receba DNS público resolvível.
- AC-01.3: `enable_dns_support` deve ser `true`.
- AC-01.4: o recurso deve receber uma tag `Name` com o valor `"${var.project_name}-vpc"`.

---

### REQ-02 — Subnets públicas

**User Story:** como aluno, quero 2 subnets públicas em AZs distintas para que a EC2 receba IP público automático e a topologia de rede atenda ao enunciado da prova.

**Acceptance Criteria:**

- AC-02.1: devem existir exatamente 2 recursos `aws_subnet` públicos, em AZs distintas dentro de `us-east-1` (`us-east-1a` e `us-east-1b`).
- AC-02.2: cada subnet pública deve ter `map_public_ip_on_launch = true`.
- AC-02.3: os CIDRs das subnets públicas são `10.0.1.0/24` (us-east-1a) e `10.0.2.0/24` (us-east-1b), sem sobreposição entre si nem com as subnets privadas.
- AC-02.4: cada subnet pública deve receber uma tag `Name` descritiva (ex.: `"${var.project_name}-public-1"` e `"${var.project_name}-public-2"`).
- AC-02.5: **ambas** as subnets públicas devem estar associadas à Route Table pública (REQ-05).

---

### REQ-03 — Subnets privadas

**User Story:** como aluno, quero 2 subnets privadas em AZs distintas para isolar o RDS da internet e satisfazer o requisito mínimo de 2 AZs do `aws_db_subnet_group`.

**Acceptance Criteria:**

- AC-03.1: devem existir exatamente 2 recursos `aws_subnet` privados, em AZs distintas dentro de `us-east-1` (`us-east-1a` e `us-east-1b`).
- AC-03.2: as subnets privadas **não** devem ter `map_public_ip_on_launch = true`.
- AC-03.3: os CIDRs das subnets privadas são `10.0.3.0/24` (us-east-1a) e `10.0.4.0/24` (us-east-1b), sem sobreposição entre si nem com as subnets públicas.
- AC-03.4: cada subnet privada deve receber uma tag `Name` descritiva (ex.: `"${var.project_name}-private-1"` e `"${var.project_name}-private-2"`).

---

### REQ-04 — Internet Gateway

**User Story:** como aluno, quero um Internet Gateway associado à VPC para que as subnets públicas tenham saída e entrada de tráfego da internet.

**Acceptance Criteria:**

- AC-04.1: deve existir um recurso `aws_internet_gateway` associado à VPC criada em REQ-01.
- AC-04.2: o recurso deve receber uma tag `Name` com o valor `"${var.project_name}-igw"`.

---

### REQ-05 — Route Table pública

**User Story:** como aluno, quero uma Route Table com rota padrão para o IGW associada a **ambas** as subnets públicas, para que o tráfego de entrada e saída da internet funcione corretamente em qualquer uma delas.

**Acceptance Criteria:**

- AC-05.1: deve existir um recurso `aws_route_table` com uma rota `destination_cidr_block = "0.0.0.0/0"` apontando para o Internet Gateway.
- AC-05.2: deve existir um recurso `aws_route_table_association` ligando essa Route Table a **cada uma das 2** subnets públicas — ou seja, 2 associações no total.
- AC-05.3: as subnets privadas **não** devem ser associadas a esta Route Table pública — elas devem usar a route table padrão da VPC, que não possui rota para o IGW.
- AC-05.4: o recurso deve receber uma tag `Name` com o valor `"${var.project_name}-rt-public"`.

---

### REQ-06 — Security Group da aplicação (`sg-app`)

**User Story:** como aluno, quero um Security Group para a instância EC2 que permita acesso HTTP público ao Moodle e SSH restrito ao IP administrativo.

**Acceptance Criteria:**

- AC-06.1: deve existir um recurso `aws_security_group` para a EC2, referenciado como `sg-app`.
- AC-06.2: regra de ingresso: TCP porta 80, origem `0.0.0.0/0` (acesso HTTP público ao Moodle).
- AC-06.3: regra de ingresso: TCP porta 22, origem `var.ssh_allowed_cidr` — SSH restrito ao IPv4 individual do aluno com máscara `/32` obrigatória; variável sem valor padrão, deve ser fornecida obrigatoriamente em `terraform.tfvars`.
- AC-06.4: regra de egresso: todo o tráfego (`0.0.0.0/0`) liberado para permitir que a EC2 acesse a internet (pull de imagens Docker, atualizações, conexão ao RDS).
- AC-06.5: o recurso deve receber uma tag `Name` com o valor `"${var.project_name}-sg-app"`.

---

### REQ-07 — Security Group do banco de dados (`sg-db`)

**User Story:** como aluno, quero um Security Group para o RDS que permita conexões PostgreSQL apenas a partir da EC2, aplicando o princípio do menor privilégio.

**Acceptance Criteria:**

- AC-07.1: deve existir um recurso `aws_security_group` para o RDS, referenciado como `sg-db`.
- AC-07.2: regra de ingresso: TCP porta 5432, origem **exclusivamente o ID do `sg-app`** (referenciado via `security_groups`, não CIDR).
- AC-07.3: **nenhuma** regra de ingresso deve usar `cidr_blocks = ["0.0.0.0/0"]` para a porta 5432.
- AC-07.4: o recurso deve receber uma tag `Name` com o valor `"${var.project_name}-sg-db"`.

---

### REQ-08 — Outputs do módulo

**User Story:** como aluno, quero que o módulo exporte os IDs dos recursos criados para que os módulos `compute` e `database` possam referenciá-los sem acoplamento direto.

**Acceptance Criteria:**

- AC-08.1: output `vpc_id` — ID da VPC criada.
- AC-08.2: output `public_subnet_ids` — lista com os IDs das subnets públicas.
- AC-08.3: output `private_subnet_ids` — lista com os IDs das subnets privadas (usada pelo módulo `database` para o `aws_db_subnet_group`).
- AC-08.4: output `sg_app_id` — ID do Security Group da EC2 (`sg-app`).
- AC-08.5: output `sg_db_id` — ID do Security Group do RDS (`sg-db`).

---

### REQ-09 — Variáveis do módulo

**User Story:** como aluno, quero que o módulo receba todas as configurações via variáveis para que os valores possam ser alterados sem modificar o código dos recursos.

**Acceptance Criteria:**

- AC-09.1: variável `project_name` (string, sem padrão) — usada nos nomes e tags dos recursos.
- AC-09.2: variável `vpc_cidr` (string, padrão `"10.0.0.0/16"`) — CIDR da VPC.
- AC-09.3: variável `public_subnet_cidrs` (list(string), padrão `["10.0.1.0/24", "10.0.2.0/24"]`) — CIDRs das subnets públicas.
- AC-09.4: variável `private_subnet_cidrs` (list(string), padrão `["10.0.3.0/24", "10.0.4.0/24"]`) — CIDRs das subnets privadas.
- AC-09.5: variável `availability_zones` (list(string), padrão `["us-east-1a", "us-east-1b"]`) — AZs onde as subnets serão criadas.
- AC-09.6: variável `ssh_allowed_cidr` (string, **sem valor padrão**) — CIDR autorizado para SSH na EC2; deve ser fornecida obrigatoriamente pelo aluno em `terraform.tfvars`; `description` deve indicar o formato esperado (`"SEU_IP/32"`) e explicar que valores abertos como `0.0.0.0/0` expõem a porta 22 à internet; deve incluir bloco `validation` para garantir que o valor seja um CIDR IPv4 válido no formato `X.X.X.X/32`.
- AC-09.7: `public_subnet_cidrs` deve conter exatamente 2 elementos, validado via bloco `validation` com `length(var.public_subnet_cidrs) == 2`.
- AC-09.8: `private_subnet_cidrs` deve conter exatamente 2 elementos, validado via bloco `validation` com `length(var.private_subnet_cidrs) == 2`.
- AC-09.9: `availability_zones` deve conter exatamente 2 elementos e as 2 AZs devem ser distintas entre si, validados em um **único** bloco `validation` com condição segura: `length(var.availability_zones) == 2 ? var.availability_zones[0] != var.availability_zones[1] : false`. A expressão condicional evita acesso a índices inexistentes quando a lista tem menos de 2 elementos.

---

### REQ-10 — Compatibilidade com AWS Academy Learner Lab

**User Story:** como aluno usando o Learn Lab, quero que o módulo não tente criar recursos IAM nem serviços indisponíveis, para evitar erros de `AccessDenied` no `terraform apply`.

**Acceptance Criteria:**

- AC-10.1: o módulo **não** deve declarar nenhum recurso do tipo `aws_iam_role`, `aws_iam_policy`, `aws_iam_user`, `aws_iam_group` ou `aws_iam_instance_profile`.
- AC-10.2: o módulo **não** deve declarar recursos `aws_route53_*`, `aws_acm_*` ou `aws_cloudfront_*`.
- AC-10.3: o módulo **não** declara credenciais AWS em seu próprio código. As credenciais temporárias STS (prefixo `ASIA`, com `aws_session_token`) são responsabilidade da configuração do provider AWS e do ambiente de execução (`~/.aws/credentials` ou variáveis de ambiente), não do módulo `networking`. A compatibilidade com o AWS Academy Learner Lab é uma restrição de integração: o módulo não deve declarar recursos que o Learn Lab bloqueia.

