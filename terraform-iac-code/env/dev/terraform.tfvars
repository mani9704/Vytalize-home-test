aws_region        = "us-east-1"

# Replace with your actual VPC ID
vpc_id            = "vpc-0abc123def456ghij"

# Replace with two or more private subnet IDs inside that VPC
private_subnet_ids = [
  "subnet-0aaa111bbb222ccc3",
  "subnet-0ddd444eee555fff6"
]

api_name    = "vytalize-vendor-api"
environment = "dev"

tags = {
  Project = "Vytalize"
  Owner   = "PlatformTeam"
  Env     = "dev"
}
