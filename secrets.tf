# Random credential generation
# Credentials are auto-generated and stored in AWS Secrets Manager.
# EC2 instances retrieve them at boot via IAM — nothing is hard-coded.

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 32
  special = true
  # Exclude characters that RDS MySQL and shell expansion doesn't allow
  override_special = "!#%^&*()-_=+[]{}|<>"
}

resource "random_string" "db_username" {
  length  = 12
  special = false
  numeric = false # RDS usernames must start with a letter; all-alpha is safest
  upper   = false
}

# Secrets Manager secret
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name}/wordpress/db-creds-${random_id.suffix.hex}"
  description             = "Auto-generated RDS credentials for the WordPress DB."
  recovery_window_in_days = 0

  tags = { Name = "${var.name}-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = random_string.db_username.result
    password = random_password.db_password.result
    dbname   = var.db_name
    engine   = "mysql"
  })
}

# IAM policy — EC2 may read only this secret

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "AllowReadDBCredentials"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.name}-secrets-read-${random_id.suffix.hex}"
  description = "Allow EC2 to read WordPress DB credentials from Secrets Manager."
  policy      = data.aws_iam_policy_document.secrets_read.json
}
