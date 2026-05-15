# ============================================================================
# COGNITO USER POOL - Admin Authentication
# ============================================================================

resource "aws_cognito_user_pool" "admin_pool" {
  name = "${var.project_name}-admin-pool"

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }

  schema {
    name                = "telegram_id"
    attribute_data_type = "String"
    mutable             = true
    required            = false
  }

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  lifecycle {
    ignore_changes = [
      schema
    ]
  }
}

resource "aws_cognito_user_pool_client" "admin_client" {
  name         = "${var.project_name}-admin-client"
  user_pool_id = aws_cognito_user_pool.admin_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"

  # Sửa lỗi thời gian Token ở đây
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30 # 30 ngày

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_cognito_user_pool_domain" "admin_domain" {
  domain       = "${var.project_name}-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.admin_pool.id
}

# Tạo admin user mặc định
resource "aws_cognito_user" "admin_user" {
  user_pool_id = aws_cognito_user_pool.admin_pool.id
  username     = "security-admin"

  attributes = {
    email = "admin@${var.project_name}.com"
  }

  temporary_password = "TempPass123!"
  depends_on = [aws_cognito_user_pool.admin_pool]
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.admin_pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.admin_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.admin_domain.domain
}