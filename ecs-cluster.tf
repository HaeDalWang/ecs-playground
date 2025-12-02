# ECS Cluster
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "6.10.0" # 최신화 2025년 12월 01일

  cluster_name = var.ecs_cluster_name

  # Cluster Settings
  cluster_setting = [
    {
      name  = "containerInsights"
      value = "enabled"
    }
  ]

  # 오토스케일링 기반 용량 제공자
  autoscaling_capacity_providers = {
    ec2 = {
      auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
      managed_termination_protection = "DISABLED"

      managed_scaling = {
        status                    = "ENABLED"
        target_capacity           = 100
        minimum_scaling_step_size = 1
        maximum_scaling_step_size = 10000
      }

      default_capacity_provider_strategy = {
        weight = 100
        base   = 1
      }
    }
  }

  # Services는 별도 파일에서 관리하므로 여기서는 생성하지 않음
  services = {}

  tags = local.tags
}

# 오토스케일링 그룹
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.2" # 최신화 2025년 12월 01일

  name = "${local.project}-ecs-asg"

  min_size         = var.ecs_min_size
  max_size         = var.ecs_max_size
  desired_capacity = var.ecs_desired_size

  vpc_zone_identifier = module.vpc.private_subnets
  health_check_type   = "ELB"

  # Launch Template
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = var.ecs_instance_type

  security_groups = [module.ecs_instance_sg.security_group_id]

  # IAM Instance Profile
  create_iam_instance_profile = true
  iam_role_name               = "${local.project}-ecs-instance-role"
  iam_role_use_name_prefix    = false

  iam_role_policies = {
    # ECS 컨테이너 인스턴스 역할 - ECS 에이전트와 Docker 데몬이 AWS API 호출에 필요
    # 참고: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # 없으면 원하는 클러스터의 조인을 하지않음
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${var.ecs_cluster_name} >> /etc/ecs/ecs.config
  EOF
  )

  tags = merge(
    local.tags,
    {
      Name = "${local.project}-ecs-instance"
    }
  )
}

# 오토스케일링 그룹의 보안그룹
module "ecs_instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.1" # 최신화 2025년 12월 01일

  name        = "${local.project}-ecs-instance-sg"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 0
      to_port                  = 65535
      protocol                 = "tcp"
      description              = "ALB access"
      source_security_group_id = module.alb_sg.security_group_id
    },
    {
      from_port                = 0
      to_port                  = 65535
      protocol                 = "tcp"
      description              = "ECS Service access"
      source_security_group_id = module.ecs_service_sg.security_group_id
    }
  ]

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = var.vpc_cidr
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
      Name = "${local.project}-ecs-instance-sg"
    }
  )
}

