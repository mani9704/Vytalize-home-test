terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
    archive = { source = "hashicorp/archive", version = ">= 2.4" }
    template = { source = "hashicorp/template", version = ">= 2.2" }
  }
}

locals { name = "${var.api_name}-${var.environment}" }

data "aws_region" "current" {}

# KMS key
resource "aws_kms_key" "this" {
  description             = "KMS for ${local.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = var.kms_key_alias
  target_key_id = aws_kms_key.this.key_id
}

# DynamoDB
resource "aws_dynamodb_table" "fast" {
  name         = var.dynamodb_table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = var.dynamodb_partition_key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.this.arn
  }
  point_in_time_recovery { enabled = true }
  attribute { name = var.dynamodb_partition_key, type = "S" }
  tags = var.tags
}

# SGs
resource "aws_security_group" "vpce_sg" {
  name        = "${local.name}-vpce-sg"
  description = "Allow HTTPS to execute-api endpoint"
  vpc_id      = var.vpc_id
  ingress { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = var.tags
}

resource "aws_vpc_endpoint" "execute_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce_sg.id]
  private_dns_enabled = true
  tags                = var.tags
}

# Lambda IAM
resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name}-lambda-exec"
  assume_role_policy = file("${path.module}/policies/lambda_assume_role.json")
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "${local.name}-cwlogs"
  role   = aws_iam_role.lambda_exec.id
  policy = file("${path.module}/policies/cw_logs_policy.json")
}

resource "aws_iam_role_policy" "lambda_ddb" {
  name = "${local.name}-ddb"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem","dynamodb:Query","dynamodb:Scan","dynamodb:PutItem","dynamodb:BatchWriteItem"], Resource = aws_dynamodb_table.fast.arn },
      { Effect = "Allow", Action = ["kms:Decrypt","kms:Encrypt","kms:GenerateDataKey"], Resource = aws_kms_key.this.arn }
    ]
  })
}

# Package Lambda (API)
data "archive_file" "lambda_api_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../app/lambda_api"
  output_path = "${path.module}/.dist/lambda_api.zip"
}

resource "aws_security_group" "lambda_sg" {
  name   = "${local.name}-lambda-sg"
  vpc_id = var.vpc_id
  egress { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] }
  tags = var.tags
}

resource "aws_lambda_function" "api_handler" {
  function_name    = "${local.name}-api"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "app.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_api_zip.output_path
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_s
  vpc_config       = { subnet_ids = var.private_subnet_ids, security_group_ids = [aws_security_group.lambda_sg.id] }
  kms_key_arn      = aws_kms_key.this.arn
  environment      = { variables = { TABLE_NAME = aws_dynamodb_table.fast.name } }
  tracing_config   = { mode = "Active" }
  depends_on       = [aws_iam_role_policy.lambda_logs, aws_iam_role_policy.lambda_ddb]
}

resource "aws_lambda_alias" "api_live" {
  name             = "live"
  function_name    = aws_lambda_function.api_handler.arn
  function_version = aws_lambda_function.api_handler.version
}

resource "aws_lambda_provisioned_concurrency_config" "pc" {
  function_name                     = aws_lambda_alias.api_live.function_name
  qualifier                         = aws_lambda_alias.api_live.name
  provisioned_concurrent_executions = var.lambda_provisioned_concurrency
}

# API Gateway (REST, Private)
resource "aws_api_gateway_rest_api" "api" {
  name        = local.name
  description = "Private Vendor API"
  endpoint_configuration { types = ["PRIVATE"] }
}

data "template_file" "api_policy" {
  template = file("${path.module}/templates/api_gateway_resource_policy.json.tmpl")
  vars     = { vpc_endpoint_id = aws_vpc_endpoint.execute_api.id }
}

resource "aws_api_gateway_rest_api_policy" "policy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  policy      = data.template_file.api_policy.rendered
}

resource "aws_api_gateway_resource" "records" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "records"
}

resource "aws_api_gateway_resource" "record_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.records.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "get_record" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.record_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "get_health" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "rec_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.record_id.id
  http_method             = aws_api_gateway_method.get_record.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "health_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.get_health.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGwInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.rec_integration,
    aws_api_gateway_integration.health_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers    = { redeploy = timestamp() }
}

resource "aws_api_gateway_stage" "stage" {
  rest_api_id          = aws_api_gateway_rest_api.api.id
  deployment_id        = aws_api_gateway_deployment.deployment.id
  stage_name           = var.environment
  xray_tracing_enabled = true
}

# Alarms
resource "aws_cloudwatch_metric_alarm" "p99_latency" {
  alarm_name          = "${local.name}-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "p99"
  threshold           = 900
  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
    Stage   = aws_api_gateway_stage.stage.stage_name
  }
}

resource "aws_cloudwatch_metric_alarm" "five_xx" {
  alarm_name          = "${local.name}-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
    Stage   = aws_api_gateway_stage.stage.stage_name
  }
}
