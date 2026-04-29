variable "region" {
  description = "AWS Region triển khai hệ thống"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Tên dự án dùng làm tiền tố cho các tài nguyên"
  type        = string
  default     = "cloud-sentinel"
}

variable "pinecone_api_key" {
  description = "API Key từ Pinecone (được nạp từ GitHub Secrets)"
  type        = string
  sensitive   = true
}

variable "pinecone_host" {
  description = "Host URL của Pinecone Index (được nạp từ GitHub Secrets)"
  type        = string
}