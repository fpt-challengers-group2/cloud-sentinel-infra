# Cloud Sentinel — Infra

Tài liệu ngắn gọn và hướng dẫn nhanh để provision hạ tầng Terraform cho hệ thống Cloud Sentinel trên AWS.

Mục tiêu
- Provision toàn bộ backend để nhận finding (GuardDuty), gọi Bedrock Agents (Supervisor → Advisor), truy vấn context/knowledge (DynamoDB + Pinecone), và lưu remediation report vào S3.

Structure (tổng quan)
- `terraform/` — IaC: providers, IAM, Lambda, Step Functions, S3, DynamoDB, Agent resources
- `src/lambda_parser/` — Lambda: parse finding
- `src/lambda_history/` — Lambda: query DynamoDB history
- `src/lambda_knowledge/` — Lambda: query Pinecone (embeddings)
- `src/lambda_invoker/` — Lambda: invoke Bedrock Agent Runtime
- `src/lambda_saver/` — Lambda: save final report to S3
- `create_index_pc.py` — helper to create Pinecone index

Key components
- Step Functions: `${project_name}-orchestrator`
- Lambdas: `${project_name}-lambda_{parser,history,knowledge,invoker,saver}`
- Bedrock Agents: `${project_name}-supervisor`, `${project_name}-advisor` (aliases: PROD)
- DynamoDB table: `cloud-sentinel-securityincidenthistory`
- S3 bucket: `${project_name}-reports-${account_id}` (prefix `remediations/`)

Quickstart (deploy)
1) Tạo Pinecone index (chỉ một lần)

   Python:

   ```bash
   pip install -r requirements.txt  # nếu cần pinecone-client
   python create_index_pc.py
   ```

   Hoặc dùng `draft.txt` làm mẫu PowerShell API.

2) Tạo `terraform/terraform.tfvars` (không commit):

   ```hcl
   region           = "ap-southeast-1"
   project_name     = "cloud-sentinel"
   pinecone_api_key = "<your-pinecone-api-key>"
   pinecone_host    = "<your-pinecone-index-host>"
   ```

3) Deploy Terraform:

   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

4) Lấy outputs:

   ```bash
   terraform output
   ```

Testing
- Start execution cho Step Function bằng event mô phỏng GuardDuty (cần `id`, `region`, `detail`).
- Sau khi chạy, kiểm tra: CloudWatch logs, Lambda logs và S3 `remediations/<finding_id>.json`.

Minimal example event

```json
{
  "id": "finding-123",
  "region": "ap-southeast-1",
  "detail": { "id": "finding-123", "type": "UnauthorizedAccess:EC2/SSHBruteForce", "severity": 7 }
}
```

Prerequisites
- Terraform >= 1.7.0
- AWS CLI authenticated with permissions to create IAM, Lambda, Step Functions, S3, DynamoDB, Bedrock resources
- Python 3.10+ (for Pinecone script)
- Pinecone account + API key

Config notes
- Variables in `terraform/variables.tf`: `region`, `project_name`, `pinecone_api_key`, `pinecone_host`.
- Keep secrets out of Git — use CI secrets, SSM Parameter Store, or AWS Secrets Manager.

Models used (reference)
- Embedding: `amazon.titan-embed-text-v1`
- Agent FM example: `anthropic.claude-3-5-sonnet-20240620-v1:0`

Operational notes
- Remote Terraform state configured in `terraform/backend.tf` (S3 + DynamoDB lock). Ensure the state bucket and lock table exist before `terraform init`.
- Consider: KMS encryption for S3, DLQ/retry for Lambdas, least-privilege IAM policies, CloudWatch alarms for failures.

Troubleshooting (quick)
- Bedrock invoke errors: check model access in region and IAM permissions (`bedrock:InvokeAgent` / `bedrock:InvokeModel`).
- Pinecone issues: verify `pinecone_api_key`, `pinecone_host`, and index `ready` state.
- Terraform backend errors: verify state bucket and lock table.
- Lambda packaging: Terraform uses `archive_file`; ensure `src/*` structure and `lambda_function.py` exist.

Development notes
- Lambda runtime: Python 3.12 (verify runtime in `terraform` if you change).
- `lambda_knowledge` may need Pinecone client in deployment package if runtime image lacks it.

Next steps
- Review `terraform/` for environment-specific adjustments and tighten IAM policies before production.

