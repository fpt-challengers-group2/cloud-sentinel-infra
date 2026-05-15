variable "region" {
  description = "AWS Region triển khai hệ thống"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Tên dự án dùng làm tiền tố cho các tài nguyên"
  type        = string
  default     = "cloud-sentinel"
}

variable "pinecone_api_key" {
  description = "API Key từ Pinecone"
  type        = string
  sensitive   = true
}

variable "pinecone_host" {
  description = "Host URL của Pinecone Index"
  type        = string
  sensitive   = true
}

variable "telegram_token" {
  description = "Telegram Bot Token"
  type        = string
  sensitive   = true
}

variable "telegram_chat_id" {
  description = "Telegram Group Chat ID"
  type        = string
  sensitive   = true
}