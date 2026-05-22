output "alb_dns_name" {
  description = "Open this in a browser — WordPress is live after instances pass health checks."
  value       = "http://${aws_lb.wordpress_alb.dns_name}"
}

output "wp_admin_url" {
  description = "WordPress admin login URL."
  value       = "http://${aws_lb.wordpress_alb.dns_name}/wp-admin"
}

output "wp_admin_secret_name" {
  description = "Retrieve WordPress admin credentials after deploy with: aws secretsmanager get-secret-value --secret-id <value> --query SecretString --output text"
  value       = "${var.name}/wordpress/wp-admin"
}

output "rds_endpoint" {
  description = "RDS host:port — injected into wp-config.php automatically at boot."
  value       = aws_db_instance.wordpress_db.endpoint
  sensitive   = true
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding DB credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "asg_name" {
  description = "Auto Scaling Group name — use in AWS Console or CLI to view instances."
  value       = aws_autoscaling_group.wordpress.name
}

output "efs_filesystem_id" {
  description = "EFS filesystem ID — shared web root for all WordPress instances."
  value       = aws_efs_file_system.wordpress.id
}

output "nat_gateway_ip" {
  description = "Elastic IP of the NAT Gateway (AZ-A) — shared by all ASG instances."
  value       = aws_eip.nat.public_ip
}

output "vpc_peering_id" {
  description = "VPC peering connection ID (VPC1 app tier <-> VPC2 data tier)."
  value       = aws_vpc_peering_connection.peer.id
}
