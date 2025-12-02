# ECS Service의 적용할 보안그룹 생성
module "ecs_service_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1" # 최신화 2025년 12월 01일

  name        = "${local.project}-ecs-service-sg"
  description = "Default ECS service"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.container_port
      to_port                  = var.container_port
      protocol                 = "tcp"
      description              = "ALB to ECS Service"
      source_security_group_id = module.alb_sg.security_group_id
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
    local.tags,
    {
      Name = "${local.project}-ecs-service-sg"
    }
  )
}
