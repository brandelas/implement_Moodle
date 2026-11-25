# Design — Módulo Terraform: database

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/database`

---

## Estrutura de Arquivos

```
terraform/modules/database/
├── main.tf         # aws_db_subnet_group + aws_db_instance
├── variables.tf    # Variáveis de entrada com sensitive nas credenciais
└── outputs.tf      # rds_endpoint, db_host, rds_port, db_name, db_username, db_password
```

> **Nota de escopo:** a configuração raiz (`terraform/main.tf`) é responsável por instanciar este módulo, passar as variáveis e conectar os outputs ao módulo `compute`. Os arquivos raiz não fazem parte desta Spec.

---

## Decisões de Design

### D-01: Não criar Security Group próprio

**Decisão:** o módulo `database` **não** declara `aws_security_group`. Recebe o `sg_db_id` do módulo `networking` via variável.

**Motivo:** o módulo `networking` já criou o `sg-db` com a regra correta: TCP 5432 com origem exclusivamente no `sg-app` via `security_groups`. Criar um segundo SG no módulo `database` seria redundante, inconsistente com a regra de menor privilégio e introduziria dependência circular implícita (database precisaria saber o ID do `sg-app` para recriar a mesma regra).

**Alinhamento:** enunciado da prova instrui "receber `sg_db_id` do módulo networking".

---

### D-02: `aws_db_subnet_group` referenciando as subnets privadas do networking

**Decisão:** o subnet group é criado neste módulo usando os IDs recebidos via `var.private_subnet_ids`.

**Motivo:** o `aws_db_subnet_group` é um recurso de banco de dados, não de rede. Mantê-lo no módulo `database` é semanticamente correto — é o banco que precisa do grupo, não a rede.

**Validação de cardinalidade no módulo:** a variável `private_subnet_ids` deve ter um bloco `validation` que exige exatamente 2 elementos (`length(var.private_subnet_ids) == 2`). Isso garante que o subnet group satisfaça o requisito mínimo da API AWS de 2 subnets.

**Responsabilidade das AZs distintas:** o Terraform não consegue verificar, em tempo de plan, se dois IDs de subnet pertencem a AZs diferentes sem consultar a API da AWS. Essa garantia é delegada ao módulo `networking`, que criou as subnets privadas em `us-east-1a` e `us-east-1b` com seus próprios blocos `validation`. Se `module.networking.private_subnet_ids` for passado diretamente, a condição de AZs distintas já foi verificada na criação do networking.

**Configuração esperada:**

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.project_name}-db-subnet-group"
    Project = var.project_name
  }
}
```

---

### D-03: `engine_version` para PostgreSQL 15

**Decisão:** usar `engine_version = "15"` como ponto de partida, mantendo o requisito de PostgreSQL 15 definido pela rubrica e pelo `docs/architecture.md`.

**Limitação conhecida:** a sintaxe `"15"` (apenas versão major) é aceita pelo provider AWS Terraform em alguns contextos, mas o comportamento exato — se o RDS aceita a versão major sem a minor ou exige uma versão minor específica — **não pode ser confirmado sem credenciais AWS ativas e acesso ao Learn Lab**. Esta compatibilidade deve ser verificada antes do `terraform apply` usando:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 15 \
  --region us-east-1 \
  --query 'DBEngineVersions[*].EngineVersion'
```

Se o apply falhar com erro de versão não reconhecida, a versão minor correta deve ser determinada a partir da saída do comando acima e declarada explicitamente (ex.: `"15.7"`), sem inventar um valor. Este ponto está registrado como pendência em `requirements.md` (AC-01.1).

---

### D-04: `skip_final_snapshot` como variável bool com padrão `true`

**Decisão:** declarar `skip_final_snapshot` como variável `bool` com padrão `true`. O `aws_db_instance` usará `skip_final_snapshot = var.skip_final_snapshot`.

**Motivo do padrão `true`:** no ambiente educacional, `terraform destroy` é executado ao final de cada sessão do Learn Lab (`docs/terraform-guide.md` §7). Se `skip_final_snapshot = false`, o RDS tentaria criar um snapshot com um nome fixo; em reexecuções, esse nome já existiria e o `destroy` falharia. O padrão `true` evita esse problema sem ação manual do aluno.

**Possibilidade de sobrescrever:** o aluno pode definir `skip_final_snapshot = false` no `terraform.tfvars` para preservar um snapshot de demonstração — por exemplo, como evidência de que o banco foi provisionado. Nesse caso, deve garantir que o nome do snapshot final seja único entre sessões. Esta variável está registrada em `requirements.md` como AC-06.8.

---

### D-05: `storage_type = "gp2"`

**Decisão:** `gp2` conforme `docs/architecture.md`.

**Motivo:** a rubrica e o gabarito especificam `gp2`. `gp3` seria mais econômico mas divergiria do requisito documentado. Seguir `gp2` garante conformidade com a rubrica.

---

### D-06: Credenciais sensíveis — risco do Terraform state

**Decisão:** `db_username` e `db_password` declaradas com `sensitive = true` e sem valor padrão. As `descriptions` documentam explicitamente o risco.

**Risco declarado:** `sensitive = true` evita que os valores apareçam no output do `terraform plan` e `terraform apply`, mas **não impede** que sejam gravados em texto legível no `terraform.tfstate`. O arquivo de state deve ser mantido fora do repositório — o `.gitignore` já cobre `terraform.tfstate` e `terraform.tfstate.backup`. Este risco deve ser documentado no `entrega.md`.

---

### D-07: Output `rds_endpoint` inclui porta

**Decisão:** exportar `aws_db_instance.main.endpoint` diretamente, sem separar o hostname.

**Motivo:** o atributo `.endpoint` do Terraform retorna `hostname:porta` (ex.: `moodle-db.xxxx.us-east-1.rds.amazonaws.com:5432`). A separação é feita na configuração raiz ao passar para o módulo `compute`:

```hcl
# terraform/main.tf — configuração raiz
module "compute" {
  rds_endpoint = module.database.db_host
  # ...
}
```

Exportar o endpoint completo mantém o módulo genérico e transfere a responsabilidade de normalização para quem consome.

---

### D-08: Variável `db_instance_class` com padrão

**Decisão:** declarar `db_instance_class` como variável com padrão `"db.t3.micro"`.

**Motivo:** permite sobrescrever via `terraform.tfvars` sem alterar o código do módulo, mantendo `db.t3.micro` como padrão exigido pela rubrica.

---

## Interface do Módulo

### Inputs (`variables.tf`)

```hcl
variable "project_name"        { type = string }
variable "private_subnet_ids"  { type = list(string) }              # sem padrão; validation: length == 2
variable "sg_db_id"            { type = string }                    # sem padrão
variable "db_name"             { type = string; default = "moodle" }
variable "db_username"         { type = string; sensitive = true }  # sem padrão
variable "db_password"         { type = string; sensitive = true }  # sem padrão
variable "db_instance_class"   { type = string; default = "db.t3.micro" }
variable "skip_final_snapshot" { type = bool;   default = true }    # ver D-04
```

### Outputs (`outputs.tf`)

```hcl
output "rds_endpoint"  # string — formato hostname:porta
output "rds_port"      # number — 5432
output "db_host"       # string — aws_db_instance.main.address (revisão)
output "db_name"       # string (revisão)
output "db_username"   # string, sensitive (revisão)
output "db_password"   # string, sensitive (revisão)
```

---

## Integração com outros módulos

```
networking → database (via configuração raiz)
  module.networking.private_subnet_ids → var.private_subnet_ids
  module.networking.sg_db_id           → var.sg_db_id

database → compute (via configuração raiz)
  module.database.db_host      → var.rds_endpoint (revisão: substitui split(":", rds_endpoint)[0])
  module.database.db_name / db_username / db_password → variáveis do compute
  module.database.rds_port     → (não usado diretamente; hardcoded como 5432 no .env)
```

---

## Pontos de Confirmação Pendentes

| # | Questão | Impacto |
|---|---|---|
| PC-01 | Confirmar se `engine_version = "15"` é aceito pelo provider AWS e pelo RDS no Learn Lab, ou se é necessária uma versão minor específica (ex.: `"15.7"`) | Se não aceito, ajustar `engine_version` em `variables.tf` ou `terraform.tfvars` antes do `terraform apply` |
