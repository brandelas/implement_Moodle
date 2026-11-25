# =============================================================================
# main.tf — Configuração raiz
# Integra os três módulos. Ordem de criação resolvida pelas referências:
#   networking -> database (subnets privadas + sg-db)
#   networking + database -> compute (subnet pública, sg-app, endpoint do RDS)
# TODO: Antes do apply, revise o terraform plan e confirme que nenhum recurso IAM aparece.
# =============================================================================

module "networking" {
  source = "./modules/networking"

  project_name     = var.project_name
  ssh_allowed_cidr = var.ssh_allowed_cidr
}

module "database" {
  source = "./modules/database"

  project_name        = var.project_name
  private_subnet_ids  = module.networking.private_subnet_ids
  sg_db_id            = module.networking.sg_db_id
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password
  db_instance_class   = var.db_instance_class
  skip_final_snapshot = var.skip_final_snapshot
}

module "compute" {
  source = "./modules/compute"

  project_name              = var.project_name
  ec2_instance_type         = var.ec2_instance_type
  iam_instance_profile_name = var.iam_instance_profile_name
  ec2_public_key            = var.ec2_public_key
  subnet_id                 = module.networking.public_subnet_ids[0]
  sg_app_id                 = module.networking.sg_app_id
  repo_url                  = var.repo_url
  repo_branch               = var.repo_branch

  # Parâmetros de conexão consumidos dos outputs do módulo database.
  rds_endpoint = module.database.db_host
  db_name      = module.database.db_name
  db_username  = module.database.db_username
  db_password  = module.database.db_password

  moodle_admin_user     = var.moodle_admin_user
  moodle_admin_password = var.moodle_admin_password
  moodle_site_name      = var.moodle_site_name
}
