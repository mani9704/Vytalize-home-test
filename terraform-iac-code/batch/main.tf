terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
    archive = { source = "hashicorp/archive", version = ">= 2.4" }
  }
}

locals { name = "ingest-${var.environment}" }

resource "aws_iam_role" "ingest_exec" {
  name               = "${local.name}-role"
  assume_role_policy = file("${path.module}/../modules/vendor_api/policies/lambda_assume_role.json")
}

resource "aws_iam_role_policy" "ingest_policy" {
  role = aws_iam_role.ingest_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem","dynamodb:BatchWriteItem"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey"], Resource = var.kms_key_arn }
    ]
  })
}

data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../app/lambda_ingest"
  output_path = "${path.module}/.dist/lambda_ingest.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name = local.name
  role          = aws_iam_role.ingest_exec.arn
  handler       = "app.handler"
  runtime       = "python3.11"
  filename      = data.archive_file.ingest_zip.output_path
  timeout       = 60
  vpc_config    = { subnet_ids = var.private_subnet_ids }
  kms_key_arn   = var.kms_key_arn
  environment   = { variables = { TABLE_NAME = var.table_name } }
}

resource "aws_cloudwatch_event_rule" "weekly" {
  name                = "weekly-systemc-ingest-${var.environment}"
  schedule_expression = "rate(7 days)"
}

resource "aws_cloudwatch_event_target" "weekly_target" {
  rule      = aws_cloudwatch_event_rule.weekly.name
  target_id = "lambda"
  arn       = aws_lambda_function.ingest.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly.arn
}
