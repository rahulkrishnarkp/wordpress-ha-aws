# Application Load Balancer

resource "aws_lb" "wordpress_alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]

  tags = { Name = "${var.name}-alb" }
}

# Target Group

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc1.id

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 30
    enabled         = true
  }

  health_check {
    path     = "/health"
    protocol = "HTTP"
    # 200 only — our Nginx /health location returns exactly 200
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-tg" }
}

# HTTP Listener 

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}
