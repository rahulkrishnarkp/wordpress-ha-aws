# EFS Filesystem 

resource "aws_efs_file_system" "wordpress" {
  creation_token   = "${var.name}-wordpress-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "${var.name}-efs" }
}

# Mount Targets

resource "aws_efs_mount_target" "a" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private_vpc1_a.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "b" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private_vpc1_b.id
  security_groups = [aws_security_group.efs_sg.id]
}
