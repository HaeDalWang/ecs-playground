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

      # ECS Cluster Auto Scaling 설정
      # managed_scaling은 ECS가 ASG의 스케일링을 자동으로 관리하는 옵션입니다.
      managed_scaling = {
        # ENABLED: ECS가 CloudWatch 메트릭을 기반으로 ASG의 DesiredCapacity를 자동 조정
        status = "ENABLED"

        # 목표 용량 사용률 (0-100%)
        # 100%: 모든 인스턴스가 최대한 활용될 때까지 스케일 아웃 (비용 효율적, 하지만 새 태스크가 PENDING 상태일 수 있음)
        # 50%: 인스턴스 사용률이 50%를 유지하도록 스케일링 (여유 용량 확보, 빠른 배포 가능, 비용 증가)
        target_capacity = 100

        # 한 번에 스케일 아웃할 수 있는 최소 인스턴스 수
        minimum_scaling_step_size = 1
        # 한 번에 스케일 아웃할 수 있는 최대 인스턴스 수 (10000 = 제한 없음 (기본값))
        maximum_scaling_step_size = 10000
      }

      # 별도 명시가 없을 경우 기본적으로 Service의 적용되는 업그레이드 전략
      default_capacity_provider_strategy = {
        # weight: 용량 제공자 간 작업 분배 비율 (0-1000)
        # weight=100, 다른 용량 제공자가 없으면 모든 작업이 이 용량 제공자에 배치됨
        weight = 100
        # 항상 유지할 최소 Task 수
        base = 1
      }
    }
  }
  
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

