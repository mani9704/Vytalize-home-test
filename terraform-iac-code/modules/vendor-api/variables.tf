variable "api_name" { type = string, description = "API name" }
variable "environment" { type = string, description = "Deployment environment" }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "kms_key_alias" { type = string, default = "alias/vytalize-kms" }

variable "lambda_memory_mb" { type = number, default = 512 }
variable "lambda_timeout_s" { type = number, default = 5 }
variable "lambda_provisioned_concurrency" { type = number, default = 20 }

variable "dynamodb_table_name" { type = string, default = "vendor_fast_store" }
variable "dynamodb_partition_key" { type = string, default = "record_id" }
variable "dynamodb_billing_mode" { type = string, default = "PAY_PER_REQUEST" }

variable "tags" { type = map(string), default = {} }
