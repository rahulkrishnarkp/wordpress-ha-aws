# AMI lookup (Amazon Linux 2 ARM64)
data "aws_ami" "amazon_linux_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

# Launch Template 

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.amazon_linux_arm.id
  instance_type = "t4g.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    region         = var.region
    secret_arn     = aws_secretsmanager_secret.db_credentials.arn
    db_host        = aws_db_instance.wordpress_db.address
    db_name        = var.db_name
    efs_id         = aws_efs_file_system.wordpress.id
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-wordpress" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name}-wordpress-vol" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress" {
  name             = "${var.name}-asg"
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  vpc_zone_identifier = [
    aws_subnet.private_vpc1_a.id,
    aws_subnet.private_vpc1_b.id,
  ]

  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]

  # ELB health checks

  # Give instances time to boot, mount EFS, and start Nginx before ALB checks begin
  # 300 s is sufficient now that /health responds immediately once Nginx starts
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  wait_for_elb_capacity = 1

  # Extend Terraform's own wait timeout beyond the default 10 min
  timeouts {
    update = "20m"
    delete = "15m"
  }

  depends_on = [
    aws_nat_gateway.nat,
    aws_efs_mount_target.a,
    aws_efs_mount_target.b,
    aws_secretsmanager_secret_version.db_credentials,
  ]

  tag {
    key                 = "Name"
    value               = "${var.name}-wordpress"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CPU-based scaling policies

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.name}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Scale out when average CPU > 80% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when average CPU < 30% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}
