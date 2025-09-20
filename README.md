# Vytalize Health – Vendor API (Private, PHI-safe)

Goal: Sub‑second API for vendors using preloaded data from a slow internal system.

- Fast path: API Gateway (Private) → Lambda (provisioned concurrency) → DynamoDB (ms‑latency)
- Cold path: Weekly batch (EventBridge → ingest Lambda) loads System C export into DynamoDB
- Security: No public internet. Private API via VPC Endpoint (execute‑api). KMS everywhere. IAM least‑privilege.

## ASCII Diagram
```
Vendor (in-VPC / peered / VPN)
        │  (Interface Endpoint: execute-api)
        ▼
 API Gateway (Private)
        │ (Lambda integration)
        ▼
    Lambda (in private subnets)
        │ (AWS SDK)
        ▼
   DynamoDB (KMS enc)
        ▲
        │  weekly ETL (EventBridge → Lambda)
        ▼
       S3 (optional landing)
```

## How this meets the test
- Performance ≤1s: read-only key lookups in DynamoDB + warm Lambda. Optional DAX if needed.
- Scalability 200+: API GW & Lambda scale; set reserved/provisioned concurrency; DynamoDB on‑demand.
- Availability ≥99.9%: regional, multi‑AZ managed services; retries & idempotence for ingest.
- Security (PHI): private API (no public), TLS, KMS, IAM least‑privilege, VPC, SGs, CloudTrail/Config.
- Maintainability: Terraform modules, typed variables, tags, env overlays.
- Observability: CloudWatch metrics/alarms; custom metric for data freshness.
- Cost: autoscaling, short Lambda timeouts, provisioned concurrency only in business hours, tuned log retention.

## Run
```bash
cd iac/envs/dev
terraform init
terraform plan
terraform apply -auto-approve
```
Test from an EC2 in the same VPC using the VPC Endpoint DNS name for execute‑api, calling the stage URL.

## API Contract (sample)
- GET /records/{id} → 200 with JSON, or 404
- GET /health → reports data freshness & status
