# Tasks — Módulo Terraform: networking

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/networking`  
**Pré-requisito:** requirements.md e design.md revisados e aprovados.

---

## Sequência de Implementação

As tasks estão ordenadas para minimizar dependências circulares e permitir validação incremental.

---

### TASK-01 — Criar estrutura de diretórios e arquivos vazios

**Objetivo:** garantir que os três arquivos obrigatórios existam antes de escrever qualquer recurso.

**Arquivos a criar:**
- `terraform/modules/networking/main.tf`
- `terraform/modules/networking/variables.tf`
- `terraform/modules/networking/outputs.tf`

**Critério de conclusão:** os três arquivos existem no sistema de arquivos; `terraform validate` não é necessário ainda (arquivos podem estar vazios).

**Requisitos cobertos:** REQ-09 (estrutura de arquivos).

---

### TASK-02 — Implementar `variables.tf`

**Objetivo:** declarar todas as variáveis de entrada do módulo, incluindo blocos `validation` para garantir a cardinalidade das listas, a distinção das AZs e o formato do CIDR de SSH.

**Conteúdo esperado:**

- `project_name` — string, sem padrão, description obrigatória.
- `vpc_cidr` — string, padrão `"10.0.0.0/16"`.
- `public_subnet_cidrs` — list(string), padrão `["10.0.1.0/24", "10.0.2.0/24"]`, com validação:
  ```hcl
  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs deve conter exatamente 2 CIDRs."
  }
  ```
- `private_subnet_cidrs` — list(string), padrão `["10.0.3.0/24", "10.0.4.0/24"]`, com validação:
  ```hcl
  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs deve conter exatamente 2 CIDRs."
  }
  ```
- `availability_zones` — list(string), padrão `["us-east-1a", "us-east-1b"]`, com validação única de cardinalidade e distinção (a condição condicional evita acesso a índices inexistentes quando a lista tem menos de 2 elementos):
  ```hcl
  validation {
    condition = length(var.availability_zones) == 2 ? (
      var.availability_zones[0] != var.availability_zones[1]
    ) : false

    error_message = "Informe exatamente 2 AZs distintas."
  }
  ```
- `ssh_allowed_cidr` — string, **sem valor padrão**, description indicando o formato `"SEU_IP/32"` e o risco de valores abertos, com validação de CIDR IPv4 e máscara `/32`:
  ```hcl
  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0)) && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.ssh_allowed_cidr))
    error_message = "Informe um único IPv4 autorizado para SSH no formato X.X.X.X/32."
  }
  ```

**Critério de conclusão:** as variáveis e validações estão declaradas corretamente em `variables.tf`; as funções usadas (`can()`, `length()`, `regex()` e `cidrhost()`) são nativas do Terraform e tecnicamente válidas. A execução de `terraform validate` não se aplica nesta task — `main.tf` e `outputs.tf` ainda estão vazios e o bloco `required_providers` ainda não foi declarado. A validação Terraform será executada a partir da TASK-03, quando o bloco `required_providers` estiver no `main.tf` e `terraform init -backend=false` tiver sido executado, conforme TASK-11.

**Requisitos cobertos:** REQ-09 (AC-09.1 a AC-09.9).

---

### TASK-03 — Implementar VPC em `main.tf`

**Objetivo:** criar o recurso `aws_vpc` com DNS habilitado. Esta é a primeira task que escreve conteúdo em `main.tf` — o bloco `required_providers` deve ser inserido no topo do arquivo antes deste recurso (ver TASK-11 para o bloco completo).

**Conteúdo esperado:**
```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}
```

**Pré-requisito para validação:** `terraform init -backend=false` deve ser executado uma vez dentro de `terraform/modules/networking/` antes de rodar `terraform validate` nesta e nas tasks subsequentes (TASK-04 a TASK-10). Esse `init` baixa o provider AWS declarado no bloco `required_providers` do `main.tf`.

**Critério de conclusão:** `terraform validate` passa; recurso referenciável por `aws_vpc.main.id`.

**Requisitos cobertos:** REQ-01 (AC-01.1 a AC-01.4).

---

### TASK-04 — Implementar subnets públicas em `main.tf`

**Objetivo:** criar as subnets públicas usando `count` sobre as listas de CIDRs e AZs.

**Conteúdo esperado:**
```hcl
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-${count.index + 1}" }
}
```

**Critério de conclusão:** `terraform validate` passa; `aws_subnet.public[*].id` é acessível.

**Requisitos cobertos:** REQ-02 (AC-02.1 a AC-02.4).

---

### TASK-05 — Implementar subnets privadas em `main.tf`

**Objetivo:** criar as subnets privadas para isolamento do RDS.

**Conteúdo esperado:**
```hcl
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${var.project_name}-private-${count.index + 1}" }
}
```

**Critério de conclusão:** `terraform validate` passa; `aws_subnet.private[*].id` é acessível.

**Requisitos cobertos:** REQ-03 (AC-03.1 a AC-03.4).

---

### TASK-06 — Implementar Internet Gateway em `main.tf`

**Objetivo:** criar e associar o IGW à VPC.

**Conteúdo esperado:**
```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}
```

**Critério de conclusão:** `terraform validate` passa; `aws_internet_gateway.main.id` é acessível.

**Requisitos cobertos:** REQ-04 (AC-04.1, AC-04.2).

---

### TASK-07 — Implementar Route Table pública e associações em `main.tf`

**Objetivo:** criar a Route Table com rota padrão para o IGW e associá-la a **ambas** as subnets públicas.

**Conteúdo esperado:**
```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)   # = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

**Critério de conclusão:** `terraform validate` passa; `aws_route_table_association.public` cria 2 associações (uma por subnet pública); subnets privadas **não** têm associação com esta Route Table.

**Requisitos cobertos:** REQ-05 (AC-05.1 a AC-05.4), REQ-02 (AC-02.5: associação das subnets públicas à Route Table).

---

### TASK-08 — Implementar Security Group `sg-app` em `main.tf`

**Objetivo:** criar o SG da EC2 com regras de ingresso HTTP e SSH e egresso irrestrito.

**Conteúdo esperado:**
```hcl
resource "aws_security_group" "sg_app" {
  name        = "${var.project_name}-sg-app"
  description = "Security Group da EC2 — Moodle"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP publico para o Moodle"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH administrativo (restrito por ssh_allowed_cidr)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "Saida irrestrita"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg-app" }
}
```

**Critério de conclusão:** `terraform validate` passa; `aws_security_group.sg_app.id` é acessível.

**Requisitos cobertos:** REQ-06 (AC-06.1 a AC-06.5).

---

### TASK-09 — Implementar Security Group `sg-db` em `main.tf`

**Objetivo:** criar o SG do RDS com ingresso TCP 5432 somente a partir do `sg-app`.

**Conteúdo esperado:**
```hcl
resource "aws_security_group" "sg_db" {
  name        = "${var.project_name}-sg-db"
  description = "Security Group do RDS — acesso somente a partir do sg-app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL somente a partir do SG da EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_app.id]
  }

  tags = { Name = "${var.project_name}-sg-db" }
}
```

**Critério de conclusão:** `terraform validate` passa; nenhuma regra usa `cidr_blocks` para a porta 5432.

**Requisitos cobertos:** REQ-07 (AC-07.1 a AC-07.4).

---

### TASK-10 — Implementar `outputs.tf`

**Objetivo:** exportar os IDs dos recursos criados para consumo pelos módulos `compute` e `database`.

**Conteúdo esperado:**
```hcl
output "vpc_id" {
  description = "ID da VPC principal"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Lista de IDs das subnets publicas"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Lista de IDs das subnets privadas (usada pelo modulo database)"
  value       = [for s in aws_subnet.private : s.id]
}

output "sg_app_id" {
  description = "ID do Security Group da EC2 (sg-app)"
  value       = aws_security_group.sg_app.id
}

output "sg_db_id" {
  description = "ID do Security Group do RDS (sg-db)"
  value       = aws_security_group.sg_db.id
}
```

**Critério de conclusão:** `terraform validate` passa; todos os outputs definidos em REQ-08 estão presentes.

**Requisitos cobertos:** REQ-08 (AC-08.1 a AC-08.5).

---

### TASK-11 — Validação local (`terraform fmt -check` e `terraform validate`)

**Objetivo:** garantir formatação padrão e ausência de erros de sintaxe antes de integrar com os outros módulos.

**Pré-requisito de provider explícito:** o módulo `terraform/modules/networking` deve declarar o provider AWS em seu próprio `main.tf`, preservando a estrutura de três arquivos já definida (sem criar `versions.tf` no módulo):

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Essa declaração explícita garante que `terraform init` baixe a versão correta do provider de forma reproduzível, sem depender de inferência implícita a partir dos tipos de recursos.

**Importante sobre o escopo da validação:** `terraform validate` executado na raiz `terraform/` **só valida os módulos que a configuração raiz chama** explicitamente via `module "..." { source = ... }`. Enquanto o `terraform/main.tf` raiz não instanciar o módulo `networking`, `terraform validate` na raiz **não** validará seus arquivos. Existem duas formas de validar o módulo `networking`:

**Opção A — Validar o módulo isoladamente (recomendado enquanto a raiz não o referencia):**

1. Executar `terraform fmt -check -recursive` a partir de `terraform/` para verificar formatação de todos os arquivos `.tf`.
2. Entrar no diretório do módulo: `cd terraform/modules/networking`.
3. Executar `terraform init -backend=false` dentro de `terraform/modules/networking/`. O Terraform lê o bloco `required_providers` declarado no `main.tf` do módulo e baixa o provider AWS `~> 5.0`.
4. Executar `terraform validate` dentro de `terraform/modules/networking/`.

> **Atenção:** `terraform init` dentro do diretório do módulo gera `.terraform/` e `.terraform.lock.hcl` locais a esse diretório. O diretório `.terraform/` **não deve ser commitado** em nenhuma circunstância. O `.terraform.lock.hcl` gerado dentro de `terraform/modules/networking/` é um artefato do teste isolado e pode ser ignorado (removido após a validação, ou simplesmente não commitado). **Não generalize essa regra para o lock file da raiz `terraform/.terraform.lock.hcl`** — esse arquivo **deve ser versionado** quando existir, pois registra a seleção de providers do projeto inteiro e garante reprodutibilidade da configuração raiz.

**Opção B — Validar a partir da raiz (após o `terraform/main.tf` instanciar o módulo):**

1. Garantir que `terraform/main.tf` contenha um bloco `module "networking" { source = "./modules/networking" ... }`.
2. Executar `terraform init -backend=false` a partir de `terraform/`.
3. Executar `terraform validate` a partir de `terraform/` — agora a raiz referencia o módulo e a validação o inclui.

> **Observação:** a Opção A é a **validação isolada** durante o desenvolvimento do módulo — verifica sintaxe e referências internas. A Opção B é a **validação integrada obrigatória** quando a configuração raiz já instancia o módulo — verifica também o encadeamento entre módulos, passagem de variáveis e consistência dos outputs. Não se exige a Opção B antes de existir a configuração raiz que chama o módulo. Quando a raiz estiver pronta, ambas devem ser executadas: primeiro a Opção A (validação isolada do módulo), depois a Opção B (validação integrada da raiz).

**Critério de conclusão:**
- Durante o desenvolvimento do módulo (antes da raiz existir): `terraform fmt -check -recursive` retorna exit 0 sem listar arquivos; `terraform validate` na Opção A retorna `Success! The configuration is valid.`
- Após a configuração raiz instanciar o módulo: `terraform validate` na Opção B também retorna `Success! The configuration is valid.` — esta passa a ser obrigatória e complementa a Opção A.

**Pré-requisito de infraestrutura:** `terraform/versions.tf` deve existir na raiz com o provider `hashicorp/aws ~> 5.0` declarado — necessário para a Opção B. A Opção A usa a declaração no `main.tf` do próprio módulo.

**Requisitos cobertos:** REQ-09, REQ-10.

---

### TASK-12 — Verificar cobertura dos testes estruturais do projeto

**Objetivo:** confirmar que os testes de estrutura do projeto passam após a criação dos arquivos do módulo `networking`.

**Passos:**
1. Executar `pytest tests/test_terraform_module_structure.py -v` a partir da raiz do repositório.
2. Verificar que os três arquivos (`main.tf`, `variables.tf`, `outputs.tf`) são detectados no módulo `networking` e que nenhum teste retorna `SKIP`.
3. Executar `pytest tests/ -v` para confirmar que os demais testes do projeto também continuam passando (nenhuma regressão introduzida).

**Critério de conclusão:** `test_terraform_module_structure.py` passa integralmente sem `SKIP`; `pytest tests/ -v` não exibe falhas novas.

**Requisitos cobertos:** critério de organização da prova (10%).

---

## Rastreabilidade Requirements → Tasks

| Requirement | Tasks |
|---|---|
| REQ-01 (VPC) | TASK-03 |
| REQ-02 (Subnets públicas) | TASK-04, TASK-07 (AC-02.5: associação à Route Table) |
| REQ-03 (Subnets privadas) | TASK-05 |
| REQ-04 (IGW) | TASK-06 |
| REQ-05 (Route Table) | TASK-07 |
| REQ-06 (sg-app) | TASK-08 |
| REQ-07 (sg-db) | TASK-09 |
| REQ-08 (Outputs) | TASK-10 |
| REQ-09 (Variáveis) | TASK-01, TASK-02 (inclui validações AC-09.7 a AC-09.9) |
| REQ-10 (Learn Lab) | TASK-11 |
| — (Organização/pytest) | TASK-12 (critério de organização da prova, 10%) |

