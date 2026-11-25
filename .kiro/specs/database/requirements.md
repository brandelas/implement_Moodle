# Requirements — Módulo Terraform: database

**Projeto:** Moodle Docker AWS Challenge  
**Disciplina:** DevOps — ADS UniFAAT 2026.2  
**Módulo:** `terraform/modules/database`  
**Região:** `us-east-1`  
**Referências:** `CHALLENGE.md`, `docs/architecture.md`, `docs/evaluation-rubric.md`, `docs/terraform-guide.md`, `.kiro/specs/networking/requirements.md`, `.kiro/specs/compute/requirements.md`

---

## Conflitos Identificados e Resoluções

| # | Conflito | Fontes | Resolução |
|---|---|---|---|
| **CP-01** | Número de subnets privadas: `docs/architecture.md` define 2 subnets privadas (`us-east-1a` e `us-east-1b`), enquanto `CHALLENGE.md` menciona "subnets privadas" no plural sem especificar quantidade. | `docs/architecture.md` vs. `CHALLENGE.md` | Usar **2 subnets privadas** em AZs distintas, pois `aws_db_subnet_group` exige no mínimo 2 AZs e `docs/architecture.md` define os CIDRs `10.0.3.0/24` e `10.0.4.0/24` (ajustados pelo módulo networking desta prova). |
| **CP-02** | O networking desta prova criou CIDRs de subnets privadas em `10.0.3.0/24` e `10.0.4.0/24`, enquanto o gabarito em `docs/architecture.md` usa `10.0.2.0/24` e `10.0.3.0/24`. | Implementação networking vs. `docs/architecture.md` | O módulo database **não precisa conhecer os CIDRs** — recebe apenas os IDs das subnets como variável. A diferença de CIDRs não impacta este módulo. |
| **CP-03** | O Security Group do RDS: a instrução desta prova diz "receber `sg_db_id` do networking", enquanto `docs/architecture.md` mostra o módulo database criando seu próprio SG. | Enunciado vs. `docs/architecture.md` | Seguir o enunciado: **usar o `sg_db_id` fornecido pelo networking**. O SG já foi criado com a regra correta (TCP 5432 apenas do `sg_app`). Criar um segundo SG seria redundante e violaria o princípio do menor privilégio. |

---

## Introdução

Este módulo é responsável por provisionar o banco de dados RDS PostgreSQL que o Moodle usará em produção na AWS. Ele consome outputs do módulo `networking` (subnets privadas e SG do banco) e exporta o endpoint e a porta para o módulo `compute`.

O módulo **não** cria recursos IAM, Security Groups próprios, subnets nem Internet Gateway.

---

## Requirements

### REQ-01 — Instância RDS PostgreSQL 15

**User Story:** como aluno, quero um banco de dados gerenciado RDS PostgreSQL 15 para que o Moodle na EC2 possa persistir dados sem gerenciar um servidor de banco de dados manualmente.

**Acceptance Criteria:**

- AC-01.1: deve existir um recurso `aws_db_instance` com `engine = "postgres"` e `engine_version = "15"`. O valor `"15"` representa a versão major sem a minor; o provider AWS aceita essa sintaxe e seleciona a versão minor mais recente disponível na região. **Ponto de atenção:** versões disponíveis variam por região e por conta AWS Academy. Se o `terraform apply` retornar erro de versão não disponível no Learn Lab, a versão minor específica (ex.: `"15.7"`) deve ser consultada via `aws rds describe-db-engine-versions --engine postgres --engine-version 15 --region us-east-1` e substituída no `terraform.tfvars`. Esta confirmação só pode ser feita com credenciais AWS ativas.
- AC-01.2: a classe da instância deve ser `db.t3.micro`, conforme `docs/evaluation-rubric.md` (p. 86) e `CHALLENGE.md` (módulo database).
- AC-01.3: o armazenamento alocado deve ser `allocated_storage = 20` GB.
- AC-01.4: o tipo de armazenamento deve ser `storage_type = "gp2"`, conforme `docs/architecture.md`.
- AC-01.5: `publicly_accessible = false` — o RDS não deve ter endpoint público.
- AC-01.6: o comportamento de snapshot final ao destruir o RDS deve ser controlável via variável `skip_final_snapshot` (bool). O valor padrão desta variável deve ser `true`, com justificativa explícita na `description`: no ambiente educacional do AWS Learn Lab, `terraform destroy` é executado ao final de cada sessão (`docs/terraform-guide.md` §7) e snapshots finais com nomes repetidos causam erro em reexecuções; além disso, o ambiente não exige recuperação de ponto-em-tempo. Se o aluno quiser preservar um snapshot — por exemplo, para demonstrar que o banco foi provisionado — pode sobrescrever via `terraform.tfvars`. Esta variável deve ser adicionada a REQ-06 (ver AC-06.8).
- AC-01.7: o recurso deve receber tags `Name` e `Project`.

---

### REQ-02 — DB Subnet Group

**User Story:** como aluno, quero que o RDS seja provisionado em subnets privadas cobrindo duas AZs distintas para satisfazer o requisito da API da AWS (`aws_db_subnet_group` exige ao menos 2 AZs).

**Acceptance Criteria:**

- AC-02.1: deve existir um recurso `aws_db_subnet_group` referenciando as subnets fornecidas por `var.private_subnet_ids`.
- AC-02.2: `var.private_subnet_ids` deve conter exatamente 2 elementos, validado por bloco `validation` na declaração da variável no `variables.tf` do módulo (`length(var.private_subnet_ids) == 2`). A garantia de que os 2 IDs pertencem a AZs distintas não pode ser verificada pelo Terraform em tempo de plan sem chamada à API da AWS; portanto, essa verificação é delegada à correta configuração do módulo networking (que já criou 2 subnets privadas em AZs distintas com seus próprios blocos `validation`). O módulo database não pode verificar AZs de IDs recebidos sem chamar a API — essa limitação deve ser documentada em `design.md`.
- AC-02.3: o subnet group deve receber tags `Name` e `Project`.

---

### REQ-03 — Security Group

**User Story:** como aluno, quero que o Security Group do RDS já exista e permita somente o tráfego necessário, sem criar um segundo SG redundante.

**Acceptance Criteria:**

- AC-03.1: o módulo **não** declara nenhum `resource "aws_security_group"` — o SG do banco (`sg-db`) já foi criado pelo módulo `networking` com a regra TCP 5432 exclusivamente a partir do `sg-app`.
- AC-03.2: o recurso `aws_db_instance` deve referenciar o SG via `var.sg_db_id`, passado como `vpc_security_group_ids = [var.sg_db_id]`.

---

### REQ-04 — Credenciais sensíveis

**User Story:** como aluno, quero que usuário e senha do banco sejam tratados como variáveis sensíveis para que não apareçam em texto claro no output do `terraform plan` e `terraform apply`.

**Acceptance Criteria:**

- AC-04.1: variável `db_username` declarada com `sensitive = true` e sem valor padrão.
- AC-04.2: variável `db_password` declarada com `sensitive = true` e sem valor padrão.
- AC-04.3: a `description` de ambas deve avisar que `sensitive = true` **não impede** o registro dos valores no `terraform.tfstate` em texto legível — o state nunca deve ser commitado no repositório.
- AC-04.4: o `terraform.tfstate` está coberto pelo `.gitignore` do projeto (`terraform.tfstate` e `terraform.tfstate.backup`). Nenhum arquivo de state deve ser commitado.

---

### REQ-05 — Outputs do módulo

**User Story:** como aluno, quero que o módulo exporte o endpoint e a porta do RDS para que o módulo `compute` possa injetar esses valores no `user_data.sh` via `templatefile()`.

**Acceptance Criteria:**

- AC-05.1: output `rds_endpoint` — valor de `aws_db_instance.main.endpoint`. O endpoint inclui a porta no formato `hostname:porta`; o hostname sem porta é exportado separadamente em `db_host` (AC-05.3).
- AC-05.2: output `rds_port` — valor de `aws_db_instance.main.port` (número inteiro, tipicamente `5432`).
- AC-05.3 *(revisão — exigido pelo enunciado da prova: "host, porta, nome, usuário, senha expostos como outputs para serem consumidos pelo módulo compute")*: outputs `db_host` (`aws_db_instance.main.address`), `db_name`, `db_username` (`sensitive = true`) e `db_password` (`sensitive = true`). O módulo `compute` recebe o hostname de `db_host`, sem `split()`.

---

### REQ-06 — Variáveis do módulo

**User Story:** como aluno, quero que todas as configurações sejam recebidas via variáveis para que o módulo seja reutilizável sem modificar seu código.

**Acceptance Criteria:**

- AC-06.1: variável `project_name` (string, sem padrão) — prefixo para nomes e tags.
- AC-06.2: variável `private_subnet_ids` (list(string), sem padrão) — IDs das subnets privadas do módulo networking.
- AC-06.3: variável `sg_db_id` (string, sem padrão) — ID do Security Group do banco (`sg-db`) do módulo networking.
- AC-06.4: variável `db_name` (string, padrão `"moodle"`) — nome do banco de dados a criar no RDS.
- AC-06.5: variável `db_username` (string, sem padrão, `sensitive = true`) — usuário master.
- AC-06.6: variável `db_password` (string, sem padrão, `sensitive = true`) — senha master. Não deve ter valor padrão.
- AC-06.7: variável `db_instance_class` (string, padrão `"db.t3.micro"`) — classe da instância RDS.
- AC-06.8: variável `skip_final_snapshot` (bool, padrão `true`) — controla se um snapshot final é criado ao destruir o RDS. O padrão `true` evita erros em reexecuções do `terraform destroy` no Learn Lab. Deve ter `description` explicando o padrão e informando como sobrescrever para `false` se um snapshot de demonstração for desejado.

---

### REQ-07 — Compatibilidade com AWS Academy Learner Lab

**User Story:** como aluno usando o Learn Lab, quero que o módulo não declare recursos bloqueados pelo ambiente para evitar erros de `AccessDenied` no `terraform apply`.

**Acceptance Criteria:**

- AC-07.1: o módulo **não** declara `aws_iam_role`, `aws_iam_policy`, `aws_iam_user` ou `aws_iam_instance_profile` como recursos.
- AC-07.2: o módulo **não** declara `aws_route53_*`, `aws_acm_*` ou `aws_cloudfront_*`.
- AC-07.3: credenciais AWS não são declaradas no módulo — são responsabilidade do provider AWS na configuração raiz.

---

### REQ-08 — Conformidade com testes existentes

**User Story:** como aluno, quero que os arquivos do módulo `database` passem nos testes estruturais do repositório.

**Acceptance Criteria:**

- AC-08.1: os três arquivos `main.tf`, `variables.tf` e `outputs.tf` devem existir em `terraform/modules/database/` — verificado por `test_terraform_module_structure.py`.
- AC-08.2: cada arquivo `.tf` em `terraform/` deve conter ao menos um comentário `# TODO:` — verificado por `test_todo_comments.py`. (Os stubs atuais já satisfazem esse critério; os arquivos finais também devem mantê-lo ou substituir por comentários funcionais.)
