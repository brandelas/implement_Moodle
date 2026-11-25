# Evidências — Prova P2 (DevOps 2026.2)

Prints reais capturados durante a execução. Cada arquivo é referenciado no `entrega.md`.

| # | Arquivo | O que deve aparecer | Entregável |
|---|---|---|---|
| 01 | `01-docker-moodle-localhost.png` | Moodle aberto em `http://localhost:8080` | 1 — Docker |
| 02 | `02-docker-compose-ps.png` | `docker compose ps` com `db` (healthy) e `moodle` (running) | 1 — Docker |
| 03 | `03-terraform-fmt-validate.png` | `terraform fmt -check -recursive` sem saída + `terraform validate` → `Success!` | 2 — Terraform |
| 04 | `04-terraform-plan.png` | `terraform plan` sem erros, com o resumo `Plan: N to add, 0 to change, 0 to destroy` | 2 — Terraform |
| 05 | `05-actions-terraform-plan.png` | Execução bem-sucedida do workflow **Terraform Plan** na aba Actions | 4 — CI/CD |
| 06 | `06-pr-comentario-plan.png` | Comentário do plano publicado na PR do fork | 4 — CI/CD |
| 07 | `07-actions-validate-lint.png` | **Terraform Validate** e **Docker Lint** verdes | 4 — CI/CD |
| 08 | `08-kiro-spec.png` | Spec aberta no Kiro (requirements/design/tasks) | 5 — Kiro |
| 09 | `09-kiro-workflow.png` | Kiro Workflow em execução ou concluído | 5 — Kiro |
| 10 | `10-pytest.png` | `pytest tests/ -v` com todos os testes passando | 6 — Organização |

Opcionais, se houver `terraform apply` autorizado:

| # | Arquivo | O que deve aparecer |
|---|---|---|
| 11 | `11-moodle-ec2.png` | Moodle acessível pelo DNS público da EC2 |
| 12 | `12-health-check-ec2.png` | Workflow **Moodle Health Check** ou `health-check.sh` com exit 0 contra a EC2 |

> Antes de salvar, confira se nenhum print mostra senhas, tokens, chaves ou o conteúdo do `.env` / `terraform.tfvars`.
