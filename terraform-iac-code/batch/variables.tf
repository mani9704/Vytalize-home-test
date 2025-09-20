variable "environment" { type = string }
variable "table_name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "kms_key_arn" { type = string }
variable "tags" { type = map(string), default = {} }
