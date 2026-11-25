# Relatório de Auditoria — Prova DevOps 2026.2

**Data:** sessão atual  
**Branch:** main | **HEAD:** 9c120e5  
**Auditor:** Kiro (análise estática + inspeção local, sem provisionamento AWS)  
**Aviso:** nenhum arquivo do projeto foi modificado durante esta auditoria, exceto a criação deste relatório.


> **Nota de revisão (registro histórico de uso do Kiro):** esta auditoria foi gerada pelo Kiro antes da conferência com o enunciado oficial da prova (`devops_20262/provas/prova-segundo-bimestre-pratica.md`). As resoluções C-01 (tipo da EC2), C-02 (gatilho do `terraform-plan.yml`) e C-05 (perfil IAM) foram revistas: a solução final usa `t3.micro`, `iam_instance_profile = "LabInstanceProfile"` e gatilhos `pull_request` + `workflow_dispatch`. As pendências das seções 5 e 8 foram implementadas. O estado atual está em `docs/architecture-design.md` e no `README.md`.
---

## 1. Resumo Executivo

### Estado geral

O projeto está em **implementação parcial avançada**. A base de qualidade é boa: o módulo `networking` está completo e sintaticamente correto, o documento de arquitetura existe e está bem estruturado, o ambiente Docker local foi validado manualmente, e as Specs Kiro para networking e compute estão documentadas com alto nível de detalhe. Entretanto, faltam componentes essenciais que impedem a entrega neste momento.

### Percentual estimado de conclusão

| Critério | Peso | Situação | Pontuação estimada |
|---|---|---|---|
| Docker local validado | 15% | Funcional (confirmado por você), sem evidência formal | ~10% |
| Terraform completo (3 módulos) | 30% | Networking completo; compute incompleto (sem `aws_instance`); database vazio | ~8% |
| `docs/architecture-design.md` | 15% | Presente, sem TODOs, com diagrama e custo | ~15% |
| `terraform-plan.yml` implementado | 15% | Stub não implementado | 0% |
| Kiro Specs e Workflows | 15% | Specs criadas; nenhum Workflow criado; sem evidências | ~5% |
| Organização, .gitignore, commits, pytest | 10% | .gitignore correto; commits parcialmente semânticos; pytest não executado | ~5% |
| **Total estimado** | **100%** | | **~43%** |

### Principais riscos

1. **Terraform não está pronto para `plan`**: faltam todos os arquivos raiz (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`) e o módulo `database` está completamente vazio.
2. **`aws_instance` ausente no módulo compute**: o `main.tf` tem apenas data sources e key pair — a instância EC2 não existe, o que torna o módulo não funcional para o desafio.
3. **`docker-compose.prod.yml` ausente**: o `user_data.sh` referencia esse arquivo, mas ele não foi criado (TASK-05 não executada).
4. **`terraform-plan.yml` é um stub não funcional**: o workflow nunca dispara e não executa nada.
5. **Nenhuma evidência de execução registrada**: não há screenshots, outputs de pytest nem logs de workflows para compor o `entrega.md`.

### Pronto para entrega?

**Não.** O projeto precisa de pelo menos: módulo database, `aws_instance` no compute, `docker-compose.prod.yml`, arquivos raiz do Terraform, `terraform-plan.yml` implementado, Kiro Workflow com evidências e `entrega.md`.

---

## 2. Matriz de Requisitos

| Requisito | Fonte | Arquivo relacionado | Situação | Evidência | Ação necessária |
|---|---|---|---|---|---|
| Docker local: `docker compose up -d` funcional | Rubrica Cat.1 | `docker/docker-compose.yml` | PARCIAL | Confirmado por você verbalmente; sem screenshot ou output formal | Registrar evidência (screenshot + health-check output) |
| `docker-compose.yml` sintaticamente válido | Rubrica Cat.1 | `docker/docker-compose.yml` | APROVADO | `docker compose config --quiet` exit 0 (confirmado em sessão anterior) | — |
| Containers atingem estado `running` | Rubrica Cat.1 | — | PARCIAL | Confirmado por você; sem screenshot de `docker compose ps` | Capturar screenshot |
| URL `localhost:8080` retorna Moodle | Rubrica Cat.1 | — | PARCIAL | Confirmado por você; sem screenshot do browser | Capturar screenshot |
| Dados persistem em volumes nomeados | Rubrica Cat.1 | `docker/docker-compose.yml` | APROVADO | Volumes declarados: `db_data`, `moodle_data`, `moodle_www` | — |
| Módulo `networking` com VPC, subnets, IGW, SGs | Rubrica Cat.2 | `terraform/modules/networking/main.tf` | APROVADO | Código implementado e sintaticamente verificado | Executar `terraform validate` |
| `terraform validate` passa | Rubrica Cat.2 | `terraform/` | NÃO VERIFICADO | Arquivos raiz ausentes — não é possível executar | Criar arquivos raiz |
| Módulo `compute` com EC2, LabRole, user_data | Rubrica Cat.2 | `terraform/modules/compute/main.tf` | REPROVADO | `aws_instance` não declarado | Implementar TASK-06 |
| Módulo `database` implementado | Rubrica Cat.2 | `terraform/modules/database/main.tf` | REPROVADO | Apenas stub com TODO | Implementar módulo database |
| `user_data.sh` instala Docker e sobe Moodle | CHALLENGE.md | `terraform/modules/compute/user_data.sh` | PARCIAL | Script existe e tem estrutura correta; `docker-compose.prod.yml` referenciado mas ausente | Criar TASK-05 |
| `docs/architecture-design.md` presente | Rubrica Cat.4 — ELIMINATÓRIO | `docs/architecture-design.md` | APROVADO | Arquivo commitado, 7 seções obrigatórias presentes | — |
| `architecture-design.md` sem TODOs | Rubrica Cat.4 | `docs/architecture-design.md` | APROVADO | Nenhum `<!-- TODO: -->` encontrado | — |
| Diagrama cobre todos os componentes obrigatórios | Rubrica Cat.4 | `docs/architecture-design.md` | APROVADO | Diagrama Mermaid presente com VPC, subnets, IGW, EC2, RDS, SGs | — |
| Decisões de design justificadas | Rubrica Cat.4 | `docs/architecture-design.md` | APROVADO | Tabela com 10 decisões e justificativas próprias | — |
| Estimativa de custo com link da calculadora | Rubrica Cat.4 | `docs/architecture-design.md` | APROVADO | Valores reais ($46,45/mês) com link gerado | — |
| `terraform-validate.yml` funcional | Rubrica Cat.3 | `.github/workflows/terraform-validate.yml` | PARCIAL | Workflow existe e está correto; nunca disparou pois `terraform/versions.tf` está ausente (condição `hashFiles`) | Criar `versions.tf` |
| `docker-lint.yml` funcional | Rubrica Cat.3 | `.github/workflows/docker-lint.yml` | NÃO VERIFICADO | Arquivo correto; nenhuma execução registrada nesta sessão | Push para verificar no GitHub Actions |
| `terraform-plan.yml` implementado e funcionando | Rubrica Cat.3 | `.github/workflows/terraform-plan.yml` | REPROVADO | Stub com `on: {}` e `if: false` — nunca executa | Implementar workflow completo |
| Kiro Spec criada | Enunciado §5 | `.kiro/specs/networking/`, `.kiro/specs/compute/` | PARCIAL | Specs de networking (completa) e compute (requirements, design, tasks) existem; não commitadas | Commitar .kiro/ |
| Kiro Workflow executado com evidência | Enunciado §5 | `.kiro/workflows/` | REPROVADO | Nenhum workflow Kiro criado | Criar e executar workflow Kiro |
| `.gitignore` cobre arquivos sensíveis | Rubrica Cat.5 | `.gitignore` | APROVADO | Cobre `.env`, `*.tfvars`, `tfstate`, `*.pem`, `*.key`, `id_rsa`, `.terraform/` | — |
| Nenhuma credencial versionada | Rubrica Cat.5 | — | APROVADO | `git ls-files` não retorna arquivos sensíveis | — |
| SG RDS restrito ao SG EC2 | Rubrica Cat.5 | `terraform/modules/networking/main.tf` | APROVADO | `security_groups = [aws_security_group.sg_app.id]` | — |
| `ssh_allowed_cidr` variável (não `0.0.0.0/0` hardcoded) | Rubrica Cat.5 | `terraform/modules/networking/variables.tf` | APROVADO | Variável sem default; validação de CIDR `/32` | — |
| `publicly_accessible = false` no RDS | Rubrica Cat.5 | `terraform/modules/database/main.tf` | NÃO VERIFICADO | Módulo database não implementado | Implementar database |
| Commits semânticos | Enunciado §6 | `.git/` | PARCIAL | 2 commits semânticos (`fix:`, `docs:`, `feat:`) de 10 total; 7 commits do template sem padrão | Continuar usando commits semânticos |
| `pytest tests/ -v` passando | Enunciado §6 | `tests/` | NÃO VERIFICADO | Dependências não instaladas nesta sessão; `test_terraform_module_structure.py` deve passar pois os 3 módulos têm os 3 arquivos obrigatórios | Executar e capturar output |
| Outputs raiz: `ec2_public_dns`, `rds_endpoint`, `vpc_id` | Rubrica Cat.2 | `terraform/outputs.tf` | REPROVADO | Arquivo não existe | Criar `terraform/outputs.tf` |
| `entrega.md` no repositório da disciplina | Enunciado §Entrega | — | REPROVADO | Arquivo não criado | Criar antes do PR |
| Pull Request aberto | Enunciado §Entrega | — | REPROVADO | PR não aberto | Abrir após concluir entregáveis |

---

## 3. Problemas Encontrados

### P-001
- **Gravidade:** CRÍTICA  
- **Arquivo:** `terraform/` (raiz)  
- **Descrição:** Nenhum dos arquivos raiz existe: `versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars.example`. Sem eles, `terraform init`, `terraform validate` e `terraform plan` falham imediatamente. O workflow `terraform-validate.yml` tem condição `if: ${{ hashFiles('terraform/versions.tf') != '' }}` — nunca dispara.  
- **Requisito violado:** Rubrica Cat.2 (35 pts), Cat.3 (5 pts pelo validate)  
- **Consequência:** 0 pts em toda a Categoria 2 e perda parcial na Categoria 3.  
- **Correção:** Criar `terraform/versions.tf`, `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf` e `terraform/terraform.tfvars.example`.

### P-002
- **Gravidade:** CRÍTICA  
- **Arquivo:** `terraform/modules/compute/main.tf`  
- **Descrição:** `aws_instance.main` não foi declarado (TASK-06 não executada). Os `outputs.tf` referenciam `aws_instance.main.public_dns` e `aws_instance.main.id`, tornando `terraform validate` inválido para o módulo.  
- **Requisito violado:** Rubrica Cat.2 — módulo compute (9 pts)  
- **Consequência:** `terraform validate` falha; módulo compute não funcional.  
- **Correção:** Implementar TASK-06.

### P-003
- **Gravidade:** CRÍTICA  
- **Arquivo:** `terraform/modules/database/`  
- **Descrição:** Todo o módulo database está como stub vazio. `main.tf`, `variables.tf` e `outputs.tf` contêm apenas comentários `# TODO:`. Nenhum recurso RDS existe.  
- **Requisito violado:** Rubrica Cat.2 — módulo database (7 pts), Cat.5 (2 pts `publicly_accessible`)  
- **Consequência:** 0 pts no módulo database; módulo compute não pode receber `rds_endpoint`.  
- **Correção:** Implementar módulo database (`aws_db_subnet_group`, `aws_db_instance`, variáveis, outputs).

### P-004
- **Gravidade:** CRÍTICA  
- **Arquivo:** `terraform/modules/compute/docker-compose.prod.yml`  
- **Descrição:** Arquivo referenciado em `user_data.sh` linha 203 (`COMPOSE_FILE=/opt/moodle/terraform/modules/compute/docker-compose.prod.yml`) mas não existe no repositório. No boot da EC2, o `docker compose up -d` falharia com "file not found".  
- **Requisito violado:** Rubrica Cat.2 — `user_data.sh` funcional  
- **Consequência:** Moodle não sobe na EC2; módulo compute sem pontuação funcional.  
- **Correção:** Executar TASK-05 — criar `docker-compose.prod.yml`.

### P-005
- **Gravidade:** CRÍTICA  
- **Arquivo:** `.github/workflows/terraform-plan.yml`  
- **Descrição:** O workflow permanece como stub com `on: {}` e `if: false`. Nunca dispara em nenhuma condição. Nenhum step implementado.  
- **Requisito violado:** Rubrica Cat.3 — `terraform-plan.yml` (4 pts)  
- **Consequência:** 0 pts neste critério; nenhuma evidência de execução possível.  
- **Correção:** Implementar o workflow com `workflow_dispatch`, checkout, configuração de credenciais AWS, setup Terraform, `terraform init -backend=false`, `terraform validate` e `terraform plan`.

### P-006
- **Gravidade:** ALTA  
- **Arquivo:** `.kiro/workflows/` (inexistente)  
- **Descrição:** Nenhum Kiro Workflow foi criado. O enunciado exige evidência de execução de Workflow Kiro para 15% da nota.  
- **Requisito violado:** Enunciado §5 — Kiro Workflows (15%)  
- **Consequência:** Perda parcial dos 15% de Kiro (Specs existem mas Workflows não).  
- **Correção:** Criar ao menos um Kiro Workflow, executá-lo e capturar evidência.

### P-007
- **Gravidade:** ALTA  
- **Arquivo:** `terraform/modules/compute/user_data.sh` — linha 125  
- **Descrição:** `TOKEN=$(curl ...)` — a variável `TOKEN` é atribuída com `$(...)` (Bash correto), mas na linha 127 é referenciada como `$${TOKEN}`, que após `templatefile()` vira `${TOKEN}`. **Isso é correto**. Porém, o próprio arquivo `user_data.sh` não é um template válido para `templatefile()` enquanto `aws_instance` não existir em `main.tf`, pois a chamada `templatefile()` só ocorre no recurso `aws_instance`. Não é um bug no script, mas a integração ainda está quebrada (P-002).  
- **Requisito violado:** Rubrica Cat.2 — funcionalidade do user_data  
- **Consequência:** Dependente de P-002 ser resolvido.  
- **Correção:** Resolver P-002 primeiro.

### P-008
- **Gravidade:** ALTA  
- **Arquivo:** `.kiro/specs/compute/`, `.kiro/specs/networking/`  
- **Descrição:** Todo o diretório `.kiro/` está não rastreado pelo Git (`?? .kiro/specs/compute/`). As Specs não estão commitadas e não aparecerão no repositório para avaliação.  
- **Requisito violado:** Enunciado §5 — uso do Kiro  
- **Consequência:** Professor não verá as Specs; evidência de uso do Kiro comprometida.  
- **Correção:** `git add .kiro/ && git commit -m "chore(kiro): adiciona specs networking e compute"`.

### P-009
- **Gravidade:** MÉDIA  
- **Arquivo:** `terraform/modules/networking/variables.tf`  
- **Descrição:** A variável `ssh_allowed_cidr` não tem `default` e tem validação de CIDR `/32`. Isso é correto por segurança, mas o `terraform plan` vai exigir o valor no `terraform.tfvars`. Como `terraform.tfvars.example` não existe ainda, o aluno pode esquecer de fornecê-lo.  
- **Requisito violado:** Funcionalidade — não bloqueia avaliação diretamente  
- **Consequência:** `terraform plan` falha com "no value for required variable" se `terraform.tfvars` não estiver preenchido.  
- **Correção:** Criar `terraform/terraform.tfvars.example` documentando `ssh_allowed_cidr = "SEU_IP/32"`.

### P-010
- **Gravidade:** MÉDIA  
- **Arquivo:** `docs/architecture-design.md`  
- **Descrição:** O documento descreve 2 subnets públicas, mas o `CHALLENGE.md` e `docs/architecture.md` (gabarito) especificam 1 subnet pública. A implementação do networking criou 2 subnets públicas. Há divergência entre o gabarito e a implementação, mas o enunciado da prova pediu "pelo menos 2 subnets públicas".  
- **Requisito violado:** Potencial divergência com gabarito do professor  
- **Consequência:** Risco baixo de perda de pontos se o professor seguir o gabarito original  
- **Correção:** Confirmar com o professor qual é o requisito correto.

### P-011
- **Gravidade:** MÉDIA  
- **Arquivo:** `terraform/modules/compute/user_data.sh` — linha 203  
- **Descrição:** O script usa `COMPOSE_FILE` como variável Bash, mas a atribuição usa `$${COMPOSE_FILE}` em vez de `COMPOSE_FILE=...`. Na linha 203, `COMPOSE_FILE=/opt/moodle/...` é atribuição direta (correto). As referências posteriores usam `"$${COMPOSE_FILE}"` que renderizarão como `"${COMPOSE_FILE}"` — correto no Bash após renderização. Porém, isso só funciona se o arquivo for processado pelo `templatefile()`, que por sua vez só existe quando `aws_instance` for declarado (P-002).  
- **Requisito violado:** Funcionalidade do user_data  
- **Consequência:** Dependente de P-002.  
- **Correção:** Resolver P-002.

### P-012
- **Gravidade:** BAIXA  
- **Arquivo:** `tests/` — nenhuma execução  
- **Descrição:** `pytest tests/ -v` nunca foi executado nesta sessão. `test_terraform_module_structure.py` deve passar pois os três módulos têm `main.tf`, `variables.tf` e `outputs.tf`. `test_todo_comments.py` pode ter problemas com o módulo database que tem apenas `# TODO:` sem conteúdo real nos arquivos `.tf` — precisa verificar.  
- **Requisito violado:** Enunciado §6 — pytest passando  
- **Consequência:** Sem evidência de testes; possível falha em testes de TODO.  
- **Correção:** Executar `pytest tests/ -v` e capturar output.

### P-013
- **Gravidade:** BAIXA  
- **Arquivo:** `terraform/modules/networking/main.tf` — comentário linha 4  
- **Descrição:** O comentário do cabeçalho diz "TODO: Implementar subnets, IGW, route tables e security groups (TASK-04 a TASK-09)" mas todas essas features já foram implementadas. O comentário desatualizado não impacta o código mas pode confundir.  
- **Requisito violado:** Organização  
- **Consequência:** Mínimo  
- **Correção:** Atualizar o comentário.

---

## 4. Conflitos Entre Documentos

### C-01: Tipo de instância EC2

| Fonte | Especificação |
|---|---|
| `docs/evaluation-rubric.md` p.85 | `t3.medium` — critério de avaliação |
| `docs/architecture.md` | `t3.medium` |
| `docs/terraform-guide.md` | `t3.medium` |
| `CHALLENGE.md` | Não menciona tipo de instância EC2 |

**Resolução:** Usar `t3.medium`. Todas as fontes que especificam o tipo apontam para `t3.medium`. O `variables.tf` do compute já usa `default = "t3.medium"`. ✅ Implementado corretamente.

### C-02: Trigger do `terraform-plan.yml`

| Fonte | Especificação |
|---|---|
| `CHALLENGE.md` | `workflow_dispatch` |
| `docs/evaluation-rubric.md` | Executa via `workflow_dispatch` |
| Stub do workflow | `on: {}` (não implementado) |

**Resolução:** Usar `workflow_dispatch`. O enunciado e a rubrica são consistentes. O stub precisa ser implementado com `on: workflow_dispatch`.

### C-03: Quantidade de subnets públicas

| Fonte | Especificação |
|---|---|
| `CHALLENGE.md` | 1 subnet pública |
| `docs/architecture.md` | 1 subnet pública (`10.0.1.0/24`) |
| Enunciado da prova (fornecido) | "pelo menos 2 subnets públicas em AZs diferentes" |
| Implementação atual | 2 subnets públicas |

**Resolução:** A implementação com 2 subnets públicas atende ao enunciado fornecido pelo professor. Há risco de divergência com o gabarito original do template. **Recomendo confirmar com o professor.** O risco é baixo, pois 2 ≥ 1.

### C-04: Requisitos do `user_data.sh`

| Fonte | Especificação |
|---|---|
| `CHALLENGE.md` | "instala o Docker na EC2 e sobe o Moodle" |
| `docs/evaluation-rubric.md` | "`user_data.sh` funcional com Docker instalado e Moodle em execução" |
| Implementação atual | Script completo com instalação Docker, Compose, clone do repo, configuração RDS, `install.php` automatizado |

**Resolução:** A implementação vai além do mínimo exigido pela rubrica — inclui instalação completa via `install.php`, o que é positivo. O risco é que o script seja mais complexo e possa falhar em algum ponto. **Recomendado:** garantir que ao menos `docker compose up -d` funcione mesmo se o `install.php` falhar (o Moodle poderia mostrar o wizard de instalação, o que ainda seria "Moodle em execução").

### C-05: `LabRole` vs `LabInstanceProfile`

| Fonte | Especificação |
|---|---|
| `CHALLENGE.md` | `data "aws_iam_instance_profile"` com `name = "LabRole"` |
| `docs/aws-learn-lab-setup.md` | `LabRole` via data source |
| Implementação atual | `data "aws_iam_instance_profile" "lab_role" { name = "LabRole" }` |

**Resolução:** Implementado corretamente com `LabRole`. ✅

---

## 5. Arquivos Ainda Pendentes

| Arquivo | Prioridade | Motivo |
|---|---|---|
| `terraform/versions.tf` | CRÍTICA | Necessário para `terraform init` e para o `terraform-validate.yml` disparar |
| `terraform/main.tf` | CRÍTICA | Instancia os 3 módulos; sem ele não há integração |
| `terraform/variables.tf` | CRÍTICA | Variáveis raiz para todos os módulos |
| `terraform/outputs.tf` | CRÍTICA | `ec2_public_dns`, `rds_endpoint`, `vpc_id` exigidos pela rubrica |
| `terraform/terraform.tfvars.example` | ALTA | Documenta as variáveis obrigatórias; evita erro no `plan` |
| `terraform/modules/compute/main.tf` (TASK-06) | CRÍTICA | `aws_instance` com `user_data`, IMDSv2, LabRole, key pair |
| `terraform/modules/compute/docker-compose.prod.yml` (TASK-05) | CRÍTICA | Referenciado pelo `user_data.sh`; sem ele o Moodle não sobe |
| `terraform/modules/database/main.tf` | CRÍTICA | `aws_db_instance` + `aws_db_subnet_group` |
| `terraform/modules/database/variables.tf` | CRÍTICA | Variáveis do banco com `sensitive = true` |
| `terraform/modules/database/outputs.tf` | CRÍTICA | `rds_endpoint`, `rds_port` |
| `.github/workflows/terraform-plan.yml` (implementado) | CRÍTICA | Substituir o stub |
| `.kiro/workflows/` | ALTA | Pelo menos 1 workflow Kiro para o critério de 15% |
| `entregas/provaSegundoBi/<RA>/entrega.md` | ALTA | Arquivo de entrega obrigatório para o PR |
| Evidências (screenshots) | ALTA | Docker funcionando, workflows executados, Kiro |

---

## 6. Testes e Validações

### Verificações executadas (análise estática local)

| Verificação | Resultado |
|---|---|
| `terraform/versions.tf` existe? | ❌ False |
| `terraform/main.tf` existe? | ❌ False |
| `terraform/modules/networking/main.tf` tem VPC, subnets, IGW, SGs | ✅ Confirmado por leitura |
| `aws_security_group.sg_db` usa `security_groups` (não `cidr_blocks`) | ✅ Linha 155 do networking/main.tf |
| `docker-compose.prod.yml` existe? | ❌ False |
| `.gitignore` cobre `.env`, `*.tfvars`, `tfstate`, `.pem` | ✅ Confirmado |
| `git ls-files` retorna arquivos sensíveis? | ✅ Nenhum arquivo sensível rastreado |
| `docs/architecture-design.md` existe? | ✅ Commitado em 75a7e77 |
| `docs/architecture-design.md` contém `<!-- TODO: -->` | ✅ Nenhum encontrado |
| `user_data.sh`: `$$(...)` residual? | ✅ Zero ocorrências após correção |
| `user_data.sh`: variáveis Terraform `${...}` corretas | ✅ `${db_password_b64}`, `${rds_endpoint}` etc. presentes |
| `user_data.sh`: variáveis Bash `$${...}` corretas | ✅ `$${TOKEN}`, `$${EC2_DNS}`, `$${COMPOSE_FILE}` etc. presentes |
| `terraform-plan.yml` stub ativo? | ❌ `on: {}` e `if: false` — nunca executa |
| Commits semânticos no histórico | PARCIAL — 3 de 10 commits usam padrão semântico |

### Verificações não executadas

| Verificação | Motivo |
|---|---|
| `terraform fmt -check -recursive` | Arquivos raiz ausentes; módulo database vazio |
| `terraform init -backend=false` nos módulos | Requer confirmação — `.terraform.lock.hcl` local seria gerado |
| `terraform validate` em qualquer módulo | `aws_instance` ausente no compute; database vazio |
| `pytest tests/ -v` | Dependências não instaladas nesta sessão |
| `docker compose config --quiet` | Já foi executado em sessão anterior — exit 0 |
| `shellcheck user_data.sh` | Ferramenta não disponível neste ambiente |

---

## 7. Evidências da Entrega

### Evidências existentes

| Evidência | Status |
|---|---|
| Docker local funcionando (Moodle em localhost:8080) | ⚠️ Confirmado verbalmente; sem screenshot formal |
| `docs/architecture-design.md` commitado | ✅ Commit 75a7e77 |
| `.gitignore` correto | ✅ |
| Specs Kiro (networking e compute) criadas | ⚠️ Existem localmente, não commitadas |
| Commits semânticos parciais | ⚠️ 3 commits no padrão |

### Evidências que ainda faltam

| Evidência | Necessária para |
|---|---|
| Screenshot de `docker compose ps` com containers `running` | Rubrica Cat.1 |
| Screenshot de `http://localhost:8080` com tela do Moodle | Rubrica Cat.1 |
| Output de `./scripts/health-check.sh http://localhost:8080` | Rubrica Cat.1 |
| Screenshot de `terraform validate` passando | Rubrica Cat.2 |
| Screenshot de `terraform plan` sem erros | Rubrica Cat.2 / Cat.3 |
| Screenshot do workflow `terraform-plan.yml` executando com sucesso | Rubrica Cat.3 |
| Screenshot do Kiro Workflow executando | Enunciado §5 |
| Screenshot das Kiro Specs no IDE | Enunciado §5 |
| Output de `pytest tests/ -v` passando | Enunciado §6 |
| `entrega.md` com todos os links e evidências | Entrega final |

---

## 8. Plano de Correção Priorizado

### Fase 1 — Problemas eliminatórios e críticos

1. **Verificar que `docs/architecture-design.md` está correto** — já existe e commitado. ✅ Feito.
2. **Commitar `.kiro/specs/`**: `git add .kiro/ && git commit -m "chore(kiro): adiciona specs networking e compute"`. Arquivos: `.kiro/specs/networking/`, `.kiro/specs/compute/`.
3. **Implementar `terraform-plan.yml`**: substituir stub com `workflow_dispatch`, checkout, AWS credentials, setup Terraform, `init -backend=false`, `validate`, `plan`. Arquivo: `.github/workflows/terraform-plan.yml`.

### Fase 2 — Infraestrutura Terraform

4. **Criar `terraform/versions.tf`**: provider `hashicorp/aws ~> 5.0`, variável de região. Dependência de tudo abaixo.
5. **Implementar módulo database** (`main.tf`, `variables.tf`, `outputs.tf`): `aws_db_subnet_group` + `aws_db_instance` PostgreSQL 15 `db.t3.micro` 20GB, `publicly_accessible = false`, outputs `rds_endpoint` e `rds_port`.
6. **Implementar TASK-06** — `aws_instance` em `compute/main.tf`: AMI data source, `t3.medium`, subnet pública, SG, LabRole, key pair, IMDSv2, `user_data = templatefile(...)`.
7. **Criar `terraform/modules/compute/docker-compose.prod.yml`** (TASK-05): serviço `moodle` com `env_file.format: raw`, porta 80, volume moodledata.
8. **Criar `terraform/main.tf`**: instancia os 3 módulos com as referências corretas (incluindo `split(":", module.database.rds_endpoint)[0]`).
9. **Criar `terraform/variables.tf`** e **`terraform/outputs.tf`**: variáveis raiz + outputs `ec2_public_dns`, `rds_endpoint`, `vpc_id`.
10. **Criar `terraform/terraform.tfvars.example`**: documentar `ssh_allowed_cidr`, credenciais do banco, etc.
11. **Executar `terraform init -backend=false` + `terraform validate`** e capturar output como evidência.

### Fase 3 — Docker e inicialização do Moodle

12. **Capturar evidências do Docker local**: screenshot de `docker compose ps`, `http://localhost:8080`, output do `health-check.sh`.
13. **Verificar comentário desatualizado** no cabeçalho de `terraform/modules/networking/main.tf` (linha 4).

### Fase 4 — CI/CD

14. **Push para GitHub** para disparar `terraform-validate.yml` (após `versions.tf` existir) e `docker-lint.yml`.
15. **Configurar secrets no GitHub** (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).
16. **Disparar `terraform-plan.yml` manualmente** via `workflow_dispatch` e capturar screenshot.

### Fase 5 — Documentação e arquitetura

17. **Atualizar `docs/architecture-design.md`** se houver divergências com a implementação final (ex.: CIDRs do database se diferentes do planejado).
18. **Atualizar comentário do cabeçalho do `networking/main.tf`**.

### Fase 6 — Testes, segurança e evidências

19. **Executar `pytest tests/ -v`** e capturar output.
20. **Criar Kiro Workflow** e executá-lo — capturar screenshot.
21. **Executar `terraform fmt -check -recursive`** e corrigir formatação se necessário.

### Fase 7 — Preparação do `entrega.md` e PR

22. **Criar `entregas/provaSegundoBi/<RA>/entrega.md`** no fork do repositório do professor com todos os links e evidências.
23. **Abrir Pull Request** com título `[Prova P2] RA: <SEU-RA> - SEU NOME`.

---

## 9. Checklist Final da Prova

| Entregável | Status | Observação |
|---|---|---|
| ✅ Fork do repositório | ✅ APROVADO | `github.com/brandelas/implement_Moodle` |
| Docker: `docker compose up -d` funcional | ⚠️ PARCIAL | Funcional mas sem evidência formal |
| Docker: Moodle em `localhost:8080` | ⚠️ PARCIAL | Confirmado verbalmente; capturar screenshot |
| Docker: persistência de dados | ✅ APROVADO | Volumes declarados |
| Terraform: módulo `networking` | ✅ APROVADO | Implementado e sintaticamente correto |
| Terraform: módulo `compute` (completo) | ❌ REPROVADO | Falta `aws_instance` (TASK-06) |
| Terraform: módulo `database` | ❌ REPROVADO | Totalmente vazio |
| Terraform: arquivos raiz | ❌ REPROVADO | Nenhum arquivo raiz existe |
| `user_data.sh` funcional | ⚠️ PARCIAL | Script existe; `docker-compose.prod.yml` ausente (TASK-05) |
| `terraform validate` passando | ❌ REPROVADO | Arquivos raiz e database ausentes |
| `docs/architecture-design.md` | ✅ APROVADO | Presente, completo, sem TODOs, com diagrama e custo |
| `terraform-plan.yml` implementado | ❌ REPROVADO | Stub não funcional |
| Kiro Spec criada | ⚠️ PARCIAL | Specs existem localmente; não commitadas |
| Kiro Workflow executado com evidência | ❌ REPROVADO | Nenhum workflow criado |
| `.gitignore` adequado | ✅ APROVADO | Cobre todos os padrões sensíveis |
| Nenhuma credencial versionada | ✅ APROVADO | `git ls-files` limpo |
| Commits semânticos | ⚠️ PARCIAL | 3 de 10 commits no padrão |
| `pytest` passando | ⚠️ NÃO VERIFICADO | Executar e capturar output |
| `entrega.md` no repositório da disciplina | ❌ REPROVADO | Não criado |
| Pull Request aberto | ❌ REPROVADO | Não aberto |

---

## 10. Parecer Final

### O projeto atende aos requisitos?

**Não neste momento.** Atende parcialmente (~43% estimado). Os pontos fortes são o módulo networking completo, o documento de arquitetura excelente, o ambiente Docker local funcional e o início das Specs Kiro. Os pontos críticos pendentes impedem a entrega.

### O que impede a entrega neste momento?

1. Módulo database completamente vazio.
2. `aws_instance` ausente no módulo compute (TASK-06 não executada).
3. `docker-compose.prod.yml` ausente — `user_data.sh` referencia um arquivo que não existe.
4. Arquivos raiz do Terraform inexistentes — `terraform plan` não pode ser executado.
5. `terraform-plan.yml` é um stub que nunca executa.

### Os cinco problemas mais importantes

| # | Problema | Impacto estimado |
|---|---|---|
| 1 | Módulo database vazio | -7 pts (Cat.2) + bloqueio do compute |
| 2 | `aws_instance` ausente no compute | -9 pts (Cat.2) + user_data inutilizável |
| 3 | Arquivos raiz do Terraform ausentes | -35 pts totais (Cat.2 inteira) se não corrigido |
| 4 | `terraform-plan.yml` não funcional | -4 pts (Cat.3) + sem evidência de CI |
| 5 | `docker-compose.prod.yml` ausente | user_data.sh falha no boot |

### O que precisa ser feito antes de qualquer deploy?

1. Implementar módulo database (`main.tf`, `variables.tf`, `outputs.tf`).
2. Implementar `aws_instance` em `compute/main.tf` (TASK-06).
3. Criar `docker-compose.prod.yml` (TASK-05).
4. Criar arquivos raiz do Terraform (`versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`).
5. Validar com `terraform init` + `terraform validate` + `terraform plan` antes de qualquer `apply`.
6. Configurar secrets AWS no GitHub antes de executar o `terraform-plan.yml`.
