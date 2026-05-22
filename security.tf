# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP/HTTPS inbound from the internet to the ALB."
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to EC2 targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-alb-sg" }
}

# EC2 Security Group

resource "aws_security_group" "ec2_sg" {
  name        = "${var.name}-ec2-sg"
  description = "HTTP from ALB only. No SSH - use SSM Session Manager."
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description     = "HTTP from ALB security group only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Outbound for NAT (yum/SSM/Secrets Manager) and RDS via peering"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-ec2-sg" }
}

# EFS Security Group

resource "aws_security_group" "efs_sg" {
  name        = "${var.name}-efs-sg"
  description = "Allow NFS (2049) inbound from EC2 instances only."
  vpc_id      = aws_vpc.vpc1.id

  egress {
    description = "Allow NFS responses back to EC2"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-efs-sg" }
}

# Cross-SG rules — added after both SGs exist to break the circular dependecy

resource "aws_security_group_rule" "ec2_to_efs" {
  description              = "NFS egress from EC2 to EFS mount targets"
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.efs_sg.id
}

resource "aws_security_group_rule" "efs_from_ec2" {
  description              = "NFS ingress to EFS from EC2 instances only"
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs_sg.id
  source_security_group_id = aws_security_group.ec2_sg.id
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  name        = "${var.name}-rds-sg"
  description = "MySQL from EC2 private subnets only (cross-VPC peering)."
  vpc_id      = aws_vpc.vpc2.id

  ingress {
    description = "MySQL from both EC2 private subnets (2-AZ)"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      var.private_subnet_vpc1_a,
      var.private_subnet_vpc1_b,
    ]
  }

  egress {
    description = "Allow response traffic back to EC2 private subnets only"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [
      var.private_subnet_vpc1_a,
      var.private_subnet_vpc1_b,
    ]
  }

  tags = { Name = "${var.name}-rds-sg" }
}
