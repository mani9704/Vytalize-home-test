module "vendor_api" {
  source                 = "../../modules/vendor_api"
  api_name               = var.api_name
  environment            = var.environment
  vpc_id                 = var.vpc_id
  private_subnet_ids     = var.private_subnet_ids
  tags                   = var.tags
}

module "batch" {
  source             = "../../batch"
  environment        = var.environment
  table_name         = module.vendor_api.dynamodb_table_name
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  kms_key_arn        = module.vendor_api.kms_key_arn
  tags               = var.tags
}
