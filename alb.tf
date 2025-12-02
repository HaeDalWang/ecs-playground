# ALB 보안그룹
module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1" # 최신화 2025년 12월 01일

  name        = "${local.project}-alb-sg"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all outbound"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = merge(
    local.tags,{
      Name = "${local.project}-alb-sg"}
  )
}

# ALB 
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.3.1" # 최신화 2025년 12월 01일

  name = "${local.project}-alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]

  enable_deletion_protection = false

  # HTTP Listener - HTTPS로 리다이렉트
  listeners = {
    # HTTP(80) -> HTTPS(443) 리다이렉트
    # redirect와 forward를 동시에 지정할 수 없으므로 redirect만 사용
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    # HTTPS Listener - Target Group으로 포워딩
    https = {
      port     = 443
      protocol = "HTTPS"
      certificate_arn = aws_acm_certificate.project.arn
      forward = {
        target_group_key = "ecs"
      }
    }
  }

  # Target Group
  target_groups = {
    ecs = {
      name                 = "${local.project}-tg"
      backend_protocol     = "HTTP"
      backend_port         = var.container_port
      target_type          = "ip"
      deregistration_delay = 30

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        interval            = 30
        path                = "/"
        protocol            = "HTTP"
        matcher             = "200"
      }

      create_attachment = false
    }
  }

  tags = merge(
    local.tags,
    {
      Name = "${local.project}-alb"
    }
  )
}

