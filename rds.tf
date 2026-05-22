# RDS Subnet Group 

resource "aws_db_subnet_group" "db_subnet" {
  name        = "${var.name}-db-subnet-group"
  description = "RDS subnet group across two AZs in VPC2."
  subnet_ids = [
    aws_subnet.private_vpc2_a.id,
    aws_subnet.private_vpc2_b.id,
  ]

  tags = { Name = "${var.name}-db-subnet-group" }
}

# RDS Instance

resource "aws_db_instance" "wordpress_db" {
  identifier        = "${var.name}-wordpress-db"
  allocated_storage = 20
  storage_type      = "gp3"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t4g.small"

  db_name  = var.db_name
  username = random_string.db_username.result
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  storage_encrypted = true

  multi_az                = true
  backup_retention_period = 0

  skip_final_snapshot = true

  performance_insights_enabled = false

  tags = { Name = "${var.name}-wordpress-db" }
}
