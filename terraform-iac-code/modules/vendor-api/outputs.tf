output "rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

# Private API base (invoke via VPC endpoint DNS)
output "rest_api_stage_invoke_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.fast.name
}

output "vpc_endpoint_id" {
  value = aws_vpc_endpoint.execute_api.id
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}
