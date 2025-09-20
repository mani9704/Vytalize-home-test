variable "aws_region" { type = string, default = "us-east-1" }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "api_name" { type = string, default = "vytalize-vendor-api" }
variable "environment" { type = string, default = "dev" }

variable "tags" {
  type = map(string)
  default = { Project = "Vytalize", Owner = "PlatformTeam", Env = "dev" }
}
