# Cloud Sentinel Infra

Hạ tầng Terraform cho hệ thống Cloud Sentinel AI trên AWS, gồm:
- Bedrock Agents (Supervisor + Advisor)
- AWS Lambda cho parser/history/knowledge/saver/invoker
- AWS Step Functions để orchestration
- DynamoDB lưu lịch sử sự cố
- S3 lưu remediation report
- Pinecone làm vector database (RAG)

## 1) Muc tieu

Repo nay dung de provision toan bo backend cho quy trinh:
1. Nhan finding (GuardDuty event) tu Step Functions input.
2. Goi Supervisor Agent phan tich su co.
3. Lay context lich su (DynamoDB) va knowledge (Pinecone).
4. Goi Advisor Agent de sinh remediation plan.
5. Luu report cuoi cung vao S3.

## 2) Cau truc repo

- `terraform/`: IaC (providers, IAM, storage, lambda, agents, step functions)
- `src/lambda_parser/`: Tach thong tin tu finding
- `src/lambda_history/`: Tra cuu tien le su co trong DynamoDB
- `src/lambda_knowledge/`: Truy van Pinecone bang embedding tu Bedrock Titan
- `src/lambda_invoker/`: Goi Bedrock Agent Runtime
- `src/lambda_saver/`: Luu report remediation vao S3
- `create_index_pc.py`: Script tao Pinecone index
- `draft.txt`: Script PowerShell mau de tao index qua API

## 3) Kien truc chinh

### Thanh phan AWS

- Step Functions state machine: `${project_name}-orchestrator`
- Lambda functions:
  - `${project_name}-lambda_parser`
  - `${project_name}-lambda_history`
  - `${project_name}-lambda_knowledge`
  - `${project_name}-lambda_saver`
  - `${project_name}-lambda_invoker`
- Bedrock Agents:
  - `${project_name}-supervisor` (alias PROD)
  - `${project_name}-advisor` (alias PROD)
- DynamoDB table: `cloud-sentinel-securityincidenthistory`
- S3 bucket: `${project_name}-reports-${account_id}`

### Luong xu ly

1. State machine goi Lambda Invoker de invoke Supervisor Agent.
2. Supervisor Agent lan luot goi action groups:
   - Finding_Parser_Tool
   - Precedent_Check
   - Knowledge_Retrieval
3. State machine parse ket qua Supervisor, sau do invoke Advisor Agent.
4. Advisor tra ve remediation report (markdown text).
5. Lambda Saver dong goi report va ghi vao S3:
   - `s3://<bucket>/remediations/<finding_id>.json`

## 4) Yeu cau truoc khi deploy

- Terraform >= 1.7.0
- AWS CLI da login va co quyen tao:
  - IAM Roles/Policies
  - Lambda
  - Step Functions
  - S3
  - DynamoDB
  - Bedrock Agent resources
- Python 3.10+ (de chay script tao Pinecone index)
- Tai khoan Pinecone va API Key hop le

Luu y: model embedding va model agent dang su dung:
- Embedding: `amazon.titan-embed-text-v1`
- Agent FM: `anthropic.claude-3-5-sonnet-20240620-v1:0`

Ban can dam bao account AWS va region cua ban duoc cap quyen Bedrock cho cac model tren.

## 5) Cau hinh bien

Khai bao trong `terraform/variables.tf`:
- `region`
- `project_name`
- `pinecone_api_key` (sensitive)
- `pinecone_host`

Gia tri runtime thuong dat trong `terraform/terraform.tfvars` hoac qua env var/CI secret.

## 6) Backend Terraform State

Repo dang cau hinh remote backend S3 + DynamoDB lock trong `terraform/backend.tf`:
- Bucket: `cloud-sentinel-tfstate`
- Key: `terraform.tfstate`
- Region: `ap-southeast-1`
- Lock table: `cloud-sentinel-lockid`

Dam bao bucket va lock table ton tai truoc khi `terraform init`.

## 7) Trien khai nhanh

### Buoc 1: Tao Pinecone index (1 lan)

Cach A - Python script:

```bash
pip install pinecone-client
python create_index_pc.py
```

Cach B - PowerShell API: tham khao `draft.txt`.

Sau khi tao xong, lay `host` cua index de gan vao `pinecone_host`.

### Buoc 2: Chuan bi tfvars

Tao file `terraform/terraform.tfvars` (khong commit):

```hcl
region           = "ap-southeast-1"
project_name     = "cloud-sentinel"
pinecone_api_key = "<your-pinecone-api-key>"
pinecone_host    = "<your-pinecone-index-host>"
```

### Buoc 3: Deploy Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Buoc 4: Lay outputs

```bash
terraform output
```

Outputs chinh:
- `s3_bucket_name`
- `step_function_arn`
- `dynamodb_table_name`

## 8) Test state machine

Ban co the start execution bang JSON event gia lap GuardDuty, toi thieu gom:
- `id`
- `region`
- `detail` (object finding)

Vi du (rut gon):

```json
{
  "id": "finding-123",
  "region": "ap-southeast-1",
  "detail": {
    "id": "finding-123",
    "type": "UnauthorizedAccess:EC2/SSHBruteForce",
    "severity": 7,
    "resource": {
      "resourceType": "Instance",
      "instanceDetails": {
        "instanceId": "i-0123456789abcdef0"
      }
    },
    "title": "SSH brute force detected",
    "description": "Multiple failed SSH attempts"
  }
}
```

Sau khi run thanh cong, kiem tra:
- CloudWatch logs cua Step Functions
- Logs cua Lambda Invoker/Saver
- File report trong S3 theo prefix `remediations/`

## 9) Bao mat va van hanh

- Khong commit secret (Pinecone API key, token, credentials) len git.
- Nen dung:
  - GitHub Actions Secrets / AWS Secrets Manager / SSM Parameter Store
  - Bien moi truong khi deploy
- IAM policy hien tai kha rong o mot so cho (vi du Bedrock invoke `Resource = "*"`), can siet theo nguyen tac least privilege khi dua production.
- Dat CloudWatch alarms cho Lambda errors va Step Functions failed executions.

## 10) Troubleshooting nhanh

- Loi Bedrock invoke:
  - Kiem tra model access trong region
  - Kiem tra role quyen `bedrock:InvokeAgent` / `bedrock:InvokeModel`
- Loi Pinecone query:
  - Kiem tra `PINECONE_API_KEY`, `PINECONE_HOST`
  - Kiem tra index da `ready`
- Loi Terraform backend:
  - Kiem tra bucket state va DynamoDB lock table ton tai
- Loi Lambda package:
  - Terraform dang zip source tu `src/*` bang `archive_file`, dam bao cau truc folder dung va co `lambda_function.py`

## 11) Ghi chu phat trien

- Runtime Lambda hien tai: Python 3.12
- `lambda_knowledge` can thu vien Pinecone trong deployment package neu runtime khong co san.
- Neu can harden he thong, uu tien:
  1. Tach secret khoi tfvars
  2. Bo sung KMS encryption cho S3 bucket
  3. Them dead-letter queue / retry strategy cho Lambda
  4. Viet integration test cho state machine flow
