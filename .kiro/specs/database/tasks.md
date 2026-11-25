# Tasks — Módulo Terraform: database

**Projeto:** Moodle Docker AWS Challenge  
**Módulo:** `terraform/modules/database`  
**Pré-requisito:** `requirements.md` e `design.md` revisados e aprovados. Módulo `networking` implementado — outputs `private_subnet_ids` e `sg_db_id` disponíveis.

---

## Sequência de Implementação

Tasks 01–03 não dependem de AWS. Task 04 requer validação local após os arquivos raiz existirem. Task 05 executa testes locais com `pytest` e **não requer credenciais AWS**. Task 06 conecta o módulo à configuração raiz.

---

## Status de execução

Atualizado após a implementação. `[x]` = concluída e conferida no código; `[ ]` = depende de execução ainda não registrada.

- [x] TASK-01 — `variables.tf`
- [x] TASK-02 — `outputs.tf`
- [x] TASK-03 — `main.tf`
- [ ] TASK-04 — Validação local
- [ ] TASK-05 — Testes estruturais (`pytest`)
- [x] TASK-06 — Integração com a configuração raiz

---

### TASK-01 — Implementar `variables.tf`

**Objetivo:** declarar as 8 variáveis de entrada do módulo com tipos, padrões e `sensitive` corretos.

**Conteúdo esperado:**

| Variável | Tipo | Padrão | `sensitive` |
|---|---|---|---|
| `project_name` | string | — | não |
| `private_subnet_ids` | list(string) | — | não |
| `sg_db_id` | string | — | não |
| `db_name` | string | `"moodle"` | não |
| `db_username` | string | — | sim |
| `db_password` | string | — | sim |
| `db_instance_class` | string | `"db.t3.micro"` | não |
| `skip_final_snapshot` | bool | `true` | não |

A variável `private_subnet_ids` deve ter bloco `validation` com `length(var.private_subnet_ids) == 2` (ver D-02).  
As `descriptions` de `db_username` e `db_password` devem avisar que `sensitive = true` **não impede** o registro no `terraform.tfstate`.  
A `description` de `skip_final_snapshot` deve explicar o padrão `true` e a possibilidade de sobrescrever para `false` (ver D-04).

**Critério de conclusão:** `variables.tf` criado; nenhuma variável sensível tem `default`; arquivo contém `# TODO:`.

**Requisitos cobertos:** REQ-06 (AC-06.1 a AC-06.8), REQ-04 (AC-04.1 a AC-04.3).

---

### TASK-02 — Implementar `outputs.tf`

**Objetivo:** declarar os outputs do módulo (revisado: parâmetros de conexão completos, exigidos pelo enunciado).

**Conteúdo esperado:**
- `rds_endpoint` → `aws_db_instance.main.endpoint`
- `rds_port` → `aws_db_instance.main.port`
- `db_host` → `aws_db_instance.main.address`
- `db_name` → `aws_db_instance.main.db_name`
- `db_username` → `aws_db_instance.main.username` (`sensitive = true`)
- `db_password` → `var.db_password` (`sensitive = true`)

As referências a `aws_db_instance.main` serão resolvidas na TASK-03; `terraform validate` completo ocorre após TASK-03.

**Critério de conclusão:** `outputs.tf` criado com os seis outputs; arquivo contém `# TODO:`.

**Requisitos cobertos:** REQ-05 (AC-05.1, AC-05.2).

---

### TASK-03 — Implementar `main.tf`

**Objetivo:** declarar o bloco `required_providers`, o subnet group e a instância RDS.

**Conteúdo esperado:**

1. Bloco `terraform { required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } } }`.
2. Recurso `aws_db_subnet_group "main"` com `subnet_ids = var.private_subnet_ids` e tags (D-02).
3. Recurso `aws_db_instance "main"` com:
   - `engine = "postgres"`, `engine_version = "15"` (D-03 — confirmar compatibilidade com provider AWS e Learn Lab antes do apply; ver PC-01 em `design.md`)
   - `instance_class = var.db_instance_class`
   - `allocated_storage = 20`, `storage_type = "gp2"` (D-05)
   - `db_name = var.db_name`
   - `username = var.db_username`, `password = var.db_password`
   - `db_subnet_group_name = aws_db_subnet_group.main.name`
   - `vpc_security_group_ids = [var.sg_db_id]` (D-01)
   - `publicly_accessible = false`
   - `skip_final_snapshot = var.skip_final_snapshot` (D-04)
   - Tags `Name` e `Project`
4. Nenhum `resource "aws_security_group"` declarado (D-01).
5. Comentário `# TODO:` obrigatório (AC-08.2).

**Critério de conclusão:** `main.tf` criado; nenhum recurso IAM declarado; `terraform validate` passa (após `terraform init -backend=false` no diretório do módulo).

**Requisitos cobertos:** REQ-01 (AC-01.1 a AC-01.7), REQ-02 (AC-02.1 a AC-02.3), REQ-03 (AC-03.1, AC-03.2), REQ-07.

---

### TASK-04 — Validação local

**Objetivo:** garantir formatação e sintaxe corretas antes da integração com a raiz.

**Passos:**
1. `terraform fmt -check -recursive terraform/` — listar arquivos fora do padrão; corrigir com `terraform fmt -recursive` se necessário.
2. **Opção A — validação isolada do módulo** (enquanto a raiz não o referencia):
   - `cd terraform/modules/database`
   - `terraform init -backend=false`
   - `terraform validate`
   - Atenção: `.terraform/` e `.terraform.lock.hcl` gerados localmente são artefatos de teste; não commitar `.terraform/`. O `.terraform.lock.hcl` local do módulo pode ser ignorado (artefato de teste isolado); o `.terraform.lock.hcl` da raiz deve ser versionado.
3. **Opção B — validação integrada** (após `terraform/main.tf` instanciar o módulo):
   - `terraform init -backend=false` a partir de `terraform/`
   - `terraform validate` a partir de `terraform/`
   - A Opção B é obrigatória quando a configuração raiz estiver pronta.

**Critério de conclusão:** `terraform fmt -check` retorna exit 0; `terraform validate` retorna `Success!` na opção escolhida.

**Pré-requisito:** `terraform/versions.tf` deve existir.

**Requisitos cobertos:** REQ-07, REQ-08.

---

### TASK-05 — Verificar testes estruturais do projeto

**Objetivo:** confirmar que a suíte `pytest` passa com os arquivos do módulo `database`.

**Passos:**
1. `pytest tests/test_terraform_module_structure.py -v` — confirmar que `main.tf`, `variables.tf` e `outputs.tf` são detectados em `terraform/modules/database/` sem `SKIP`.
2. `pytest tests/test_todo_comments.py -v` — confirmar que todos os arquivos `.tf` em `terraform/modules/database/` contêm `# TODO:`.
3. `pytest tests/ -v` — confirmar que nenhum outro teste regrediu.

**Critério de conclusão:** todos os testes passam sem `SKIP` nem falha nova.

**Requisitos cobertos:** REQ-08 (AC-08.1, AC-08.2).

---

### TASK-06 — Integrar com a configuração raiz

**Objetivo:** conectar o módulo `database` ao `terraform/main.tf` e expor seus outputs na raiz.

**Conteúdo esperado em `terraform/main.tf`:**

```hcl
module "database" {
  source                = "./modules/database"
  project_name          = var.project_name
  private_subnet_ids    = module.networking.private_subnet_ids
  sg_db_id              = module.networking.sg_db_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  db_instance_class     = var.db_instance_class
  skip_final_snapshot   = var.skip_final_snapshot
}
```

**Outputs raiz a expor:** `rds_endpoint = module.database.rds_endpoint` (exigido pela rubrica).

**Referência para o módulo compute:**

```hcl
module "compute" {
  rds_endpoint = module.database.db_host
  # ...
}
```

**Critério de conclusão:** `terraform validate` a partir de `terraform/` passa (Opção B da TASK-04); `module.database.*` referenciável nos outputs da raiz.

**Requisitos cobertos:** REQ-05, REQ-06.

---

## Rastreabilidade Requirements → Tasks

| Requirement | Tasks principais |
|---|---|
| REQ-01 (RDS PostgreSQL 15) | TASK-03 |
| REQ-02 (DB Subnet Group) | TASK-03 |
| REQ-03 (SG via variável, sem criar SG) | TASK-01, TASK-03 |
| REQ-04 (Credenciais sensíveis) | TASK-01 |
| REQ-05 (Outputs) | TASK-02, TASK-06 |
| REQ-06 (Variáveis) | TASK-01 (8 variáveis, incluindo `skip_final_snapshot`) |
| REQ-07 (Learn Lab) | TASK-03 |
| REQ-08 (Testes estruturais) | TASK-01, TASK-02, TASK-03, TASK-05 |

## Rastreabilidade Decisões de Design → Tasks

| Decisão | Task |
|---|---|
| D-01 (sem SG próprio) | TASK-01, TASK-03 |
| D-02 (subnet group no módulo database) | TASK-03 |
| D-03 (`engine_version = "15"`) | TASK-03 |
| D-04 (`skip_final_snapshot` variável bool, padrão true) | TASK-01, TASK-03, TASK-06 |
| D-05 (`storage_type = "gp2"`) | TASK-03 |
| D-06 (risco do state) | TASK-01 |
| D-07 (endpoint com porta, split na raiz) | TASK-02, TASK-06 |
| D-08 (`db_instance_class` variável) | TASK-01 |
