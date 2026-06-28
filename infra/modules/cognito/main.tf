resource "aws_cognito_user_pool" "this" {
  name                     = var.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.name}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30
  auth_session_validity         = 3
  supported_identity_providers  = ["COGNITO"]

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
