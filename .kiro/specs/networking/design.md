# Design — Módulo Terraform: networking

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/networking`

---

## Estrutura de Arquivos

```
terraform/
└── modules/
    └── networking/
        ├── main.tf         # Recursos AWS: VPC, subnets, IGW, route tables, SGs
        ├── variables.tf    # Declaração de todas as variáveis de entrada
        └── outputs.tf      # Exportação dos IDs para consumo pelos outros módulos
```

Nenhum arquivo adicional é necessário. O módulo não usa `locals.tf` separado — eventuais `locals` ficam no `main.tf` para manter a estrutura mínima exigida pelo desafio.

> **Nota de escopo:** a estrutura acima é apenas do módulo `networking`. Arquivos da raiz do projeto Terraform — `terraform/versions.tf` (declaração do provider), `terraform/main.tf` (instanciação dos módulos), `terraform/variables.tf`, `terraform/outputs.tf` e `terraform/terraform.tfvars.example` — não fazem parte desta Spec. Eles são referenciados em TASK-11 (Opção B) como pré-requisitos para a validação integrada, mas sua implementação é responsabilidade das Specs dos módulos `compute` e `database` e da configuração raiz.

---

## Decisões de Design

### D-01: 2 subnets públicas obrigatórias

**Decisão:** criar exatamente 2 subnets públicas em AZs distintas (`us-east-1a` e `us-east-1b`).

**Motivo:** o enunciado da prova define explicitamente "pelo menos 2 subnets públicas em AZs diferentes". Esta é a especificação vigente para a entrega — não há ambiguidade ou ponto pendente de confirmação.

**Impacto no módulo compute:** a instância EC2 única usará `public_subnet_ids[0]` (`10.0.1.0/24`, `us-east-1a`). A segunda subnet pública satisfaz o requisito da prova e fica disponível caso a topologia evolua.

---

### D-02: Criação de subnets via `count` indexado

**Decisão:** usar `count` indexado sobre as listas `var.public_subnet_cidrs` e `var.private_subnet_cidrs`, combinado com `var.availability_zones`.

**Motivo:** mais simples de ler e manter do que `for_each` para este caso de uso. As listas são paralelas por índice (índice 0 → AZ 0, índice 1 → AZ 1), o que é idiomático em módulos de rede Terraform.

**Restrição de cardinalidade:** as três listas — `public_subnet_cidrs`, `private_subnet_cidrs` e `availability_zones` — devem conter **exatamente 2 elementos** cada, e as 2 AZs devem ser distintas entre si. Para `public_subnet_cidrs` e `private_subnet_cidrs`, a verificação usa `length(var...) == 2`. Para `availability_zones`, a cardinalidade e a distinção são combinadas em um **único** bloco `validation` com expressão condicional segura — `length(var.availability_zones) == 2 ? var.availability_zones[0] != var.availability_zones[1] : false` — para evitar acesso a índices inexistentes quando a lista tem menos de 2 elementos. Essas restrições garantem que `count.index` sempre varia de 0 a 1 e o pareamento CIDR↔AZ é determinístico.

**Consequência nos outputs:** `public_subnet_ids` e `private_subnet_ids` serão listas (`[for s in aws_subnet.public : s.id]`), compatíveis com o que o módulo `database` espera para o `aws_db_subnet_group`.

---

### D-03: Security Group sg-db — origem via `security_groups`

**Decisão:** a regra de ingresso da porta 5432 no `sg-db` usará `security_groups = [aws_security_group.sg_app.id]`, não `cidr_blocks`.

**Motivo:** referenciar o SG da EC2 como origem é mais seguro e idiomático. Garante que apenas instâncias com aquele SG específico possam conectar ao banco, independente de IP. Alinhado com `docs/security-practices.md` §2.1 e `docs/architecture-design.md` §Segurança.

---

### D-04: Tags em recursos que suportam a propriedade

**Decisão:** todos os recursos AWS que suportam a propriedade `tags` receberão ao menos a tag `Name` com prefixo `var.project_name`. Recursos como `aws_route_table_association`, que não aceitam `tags`, são naturalmente excluídos.

**Motivo:** facilita a identificação dos recursos no console AWS durante o desafio e é uma boa prática básica de IaC. Não há exigência explícita na rubrica, mas contribui para a Categoria 5 (boas práticas de segurança e organização).

---

### D-05: CIDRs das subnets

| Subnet | CIDR | AZ |
|---|---|---|
| Pública 1 | `10.0.1.0/24` | `us-east-1a` |
| Pública 2 | `10.0.2.0/24` | `us-east-1b` |
| Privada 1 | `10.0.3.0/24` | `us-east-1a` |
| Privada 2 | `10.0.4.0/24` | `us-east-1b` |

Os CIDRs públicos seguem o padrão do `docs/architecture.md` para a primeira subnet. A segunda subnet pública ocupa `10.0.2.0/24`. Os CIDRs privados foram deslocados para `10.0.3.0/24` e `10.0.4.0/24` para evitar sobreposição com a segunda subnet pública.

### D-06: `ssh_allowed_cidr` obrigatória, sem valor padrão, com validação

**Decisão:** a variável `ssh_allowed_cidr` não terá `default`. O bloco `validation` verificará que o valor é um CIDR IPv4 válido no formato `X.X.X.X/32` usando `can(cidrhost(var.ssh_allowed_cidr, 0))` e uma expressão regular que exige o sufixo `/32`.

**Motivo:** SSH exposto para `0.0.0.0/0` é risco de segurança documentado. Remover o padrão força o aluno a fornecer explicitamente o valor no `terraform.tfvars`, tornando a decisão consciente. O bloco `validation` evita que valores malformados cheguem ao `terraform apply`.

**Consequência:** o `terraform.tfvars` precisará incluir `ssh_allowed_cidr = "SEU_IP/32"`. O `terraform.tfvars.example` documentará o formato esperado.

---

### D-07: Credenciais STS — responsabilidade do provider, não do módulo

**Decisão:** o módulo `networking` **não** declara credenciais AWS em seu próprio código. As credenciais temporárias STS (prefixo `ASIA`, com `aws_session_token`) são configuradas no nível do provider AWS e do ambiente de execução — via `~/.aws/credentials`, variáveis de ambiente (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) ou secrets do GitHub Actions.

**Motivo:** credenciais são dados de configuração do ambiente, não lógica de infraestrutura. Declará-las dentro de um módulo filho é anti-padrão e introduz risco de exposição. A declaração do `provider "aws"` com `region` fica no `terraform/versions.tf` da raiz, e as credenciais são lidas automaticamente da cadeia de provedores padrão do AWS SDK.

**Compatibilidade com AWS Academy como restrição de integração:** o módulo respeita as restrições do Learn Lab não declarando recursos bloqueados (`aws_iam_*`, `aws_route53_*`, `aws_acm_*`, `aws_cloudfront_*`). As credenciais temporárias são fornecidas externamente ao módulo, conforme `docs/aws-learn-lab-setup.md`.

---

## Diagrama do Módulo

```
┌─────────────────────────────────────────────────────────────┐
│  VPC 10.0.0.0/16                                            │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ Subnet Pública 1 │  │ Subnet Pública 2 │                │
│  │ 10.0.1.0/24      │  │ 10.0.2.0/24      │                │
│  │ us-east-1a       │  │ us-east-1b       │                │
│  │ [sg-app]  [EC2]  │  │ (reserva)        │                │
│  └────────┬─────────┘  └──────────────────┘                │
│           │ Route Table Pública (0.0.0.0/0 → IGW)          │
│           │                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ Subnet Privada 1 │  │ Subnet Privada 2 │                │
│  │ 10.0.3.0/24      │  │ 10.0.4.0/24      │                │
│  │ us-east-1a       │  │ us-east-1b       │                │
│  │ [sg-db]   [RDS]  │  │ (subnet group)   │                │
│  └──────────────────┘  └──────────────────┘                │
│                                                             │
│  Internet Gateway ←──── sg-app (80, 22) ────→ Internet     │
│                          sg-db  (5432 ← sg-app apenas)      │
└─────────────────────────────────────────────────────────────┘
```

---

## Interface do Módulo

### Inputs (`variables.tf`)

```hcl
variable "project_name"          { type = string }  # sem default — obrigatória
variable "vpc_cidr"               { type = string; default = "10.0.0.0/16" }
variable "public_subnet_cidrs"    { type = list(string); default = ["10.0.1.0/24", "10.0.2.0/24"] }  # validation: length == 2
variable "private_subnet_cidrs"   { type = list(string); default = ["10.0.3.0/24", "10.0.4.0/24"] }  # validation: length == 2
variable "availability_zones"     { type = list(string); default = ["us-east-1a", "us-east-1b"] }   # validation: length == 2 e AZs distintas
variable "ssh_allowed_cidr"       { type = string }  # sem default — obrigatória; validation: CIDR IPv4 /32
```

### Outputs (`outputs.tf`)

```hcl
output "vpc_id"             # string
output "public_subnet_ids"  # list(string)
output "private_subnet_ids" # list(string)
output "sg_app_id"          # string
output "sg_db_id"           # string
```

---

## Pontos de Confirmação Pendentes

Nenhum. As decisões de design estão fechadas conforme o enunciado da prova revisado.

