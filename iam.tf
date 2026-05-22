# IAM Role for EC2
# Grants:
#   1. SSM Session Manager — shell access without SSH or a bastion
#   2. Secrets Manager — read the DB credentials secret
#   3. EFS — mount filesystem using instance profile (no access keys)

resource "aws_iam_role" "ec2_role" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.name}-ec2-role" }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "secrets" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_role_policy_attachment" "secrets_wp_write" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_write_wp.arn
}

resource "aws_iam_role_policy_attachment" "efs" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.efs_mount.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EFS mount policy 
data "aws_iam_policy_document" "efs_mount" {
  statement {
    sid    = "AllowEFSMount"
    effect = "Allow"

    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeMountTargets",
    ]

    resources = [aws_efs_file_system.wordpress.arn]
  }
}

resource "aws_iam_policy" "efs_mount" {
  name        = "${var.name}-efs-mount"
  description = "Allow EC2 instances to mount the WordPress EFS filesystem."
  policy      = data.aws_iam_policy_document.efs_mount.json
}

# WP admin secret write policy (first boot only) 

data "aws_iam_policy_document" "secrets_write_wp" {
  statement {
    sid    = "AllowWriteWPAdminSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      "arn:aws:secretsmanager:${var.region}:*:secret:${var.name}/wordpress/wp-admin*"
    ]
  }
}

resource "aws_iam_policy" "secrets_write_wp" {
  name        = "${var.name}-secrets-write-wp-${random_id.suffix.hex}"
  description = "Allow EC2 to store WordPress admin credentials in Secrets Manager at first boot."
  policy      = data.aws_iam_policy_document.secrets_write_wp.json
}
