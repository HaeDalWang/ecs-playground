# ECS Service 및 Task Definition 정의
# app-definitions의 JSON 파일을 읽어서 Task Definition과 Service를 한 번에 생성

locals {
  # 앱 목록
  apps = [
    "fastapi-logger"
  ]

  # 각 앱의 정의 파일 읽기 및 파싱 (Task Definition)
  app_definitions = {
    for app in local.apps : app => jsondecode(file("${path.module}/app-definitions/${app}.json"))
  }

  # 각 앱의 라우팅 정의 파일 읽기 및 파싱 (ALB Routing)
  # app-routing 디렉토리가 있으면 읽고, 없으면 빈 맵
  routing_apps = [
    "fastapi-logger"
  ]
  
  app_routing_definitions = {
    for app in local.routing_apps : app => jsondecode(file("${path.module}/app-routing/${app}.json"))
    if fileexists("${path.module}/app-routing/${app}.json")
  }

  # ============================================================================
  # ECS SERVICE + TASK DEFINITION 통합 생성
  # ============================================================================
  # JSON 파일 하나로 Task Definition과 Service 설정을 모두 정의합니다.
  # ============================================================================
  ecs_services = {
    for app_name, app_config in local.app_definitions : "${local.project}-${app_name}" => {

      # ============================================================================
      # TASK DEFINITION 설정 (JSON에서 직접 읽어옴)
      # ============================================================================
      # Task Definition - 리소스 할당
      cpu    = app_config.cpu
      memory = app_config.memory

      # Task Definition - 컨테이너 정의
      container_definitions = {
        "${app_config.container_name}" = {
          essential = true
          image     = app_config.image

          # 컨테이너 포트 매핑
          portMappings = [
            {
              name          = "${app_config.container_name}-${app_config.container_port}"
              containerPort = app_config.container_port
              protocol      = "tcp"
            }
          ]

          # CloudWatch Logs 설정
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "/ecs/${var.ecs_cluster_name}/${app_name}"
              "awslogs-region"        = data.aws_region.current.id
              "awslogs-stream-prefix" = "ecs"
            }
          }

          # 환경 변수
          environment = try(app_config.environment, []) != null && length(try(app_config.environment, [])) > 0 ? [
            for env in app_config.environment : {
              name  = env.name
              value = env.value
            }
          ] : []

          # CloudWatch Log Group 자동 생성
          enable_cloudwatch_logging              = true
          create_cloudwatch_log_group            = true
          cloudwatch_log_group_retention_in_days = 7
        }
      }

      # Task Definition - 호환성 및 네트워크 모드
      requires_compatibilities = ["EC2"]  # EC2 또는 FARGATE
      network_mode            = "awsvpc" # awsvpc, bridge, host, none

      # Task Definition - IAM Roles
      create_task_exec_iam_role = true
      task_exec_iam_role_name   = "${local.project}-${app_name}-task-execution-role"
      create_tasks_iam_role     = true
      tasks_iam_role_name       = "${local.project}-${app_name}-task-role"

      # ============================================================================
      # ECS SERVICE 설정 (JSON에서 직접 읽어옴)
      # ============================================================================
      # Service - 태스크 개수 및 배포 설정
      desired_count                      = app_config.desired_count
      deployment_minimum_healthy_percent = app_config.deployment_minimum_healthy_percent
      deployment_maximum_percent         = app_config.deployment_maximum_percent
      health_check_grace_period_seconds  = app_config.health_check_grace_period_seconds

      # Service - 배포 Circuit Breaker (배포 실패 시 자동 롤백)
      deployment_circuit_breaker = {
        enable   = true
        rollback = true
      }

      # Service - 태그 및 명령 실행 설정
      enable_ecs_managed_tags = true
      enable_execute_command  = false

      # Service - 네트워크 배치 설정
      subnet_ids         = module.vpc.private_subnets
      security_group_ids = [module.ecs_service_sg.security_group_id]
      assign_public_ip   = false

      # Service - Launch Type 및 Capacity Provider 전략
      launch_type = "EC2"
      capacity_provider_strategy = {
        ec2 = {
          capacity_provider = "ec2"
          weight            = 100
          base              = 1
        }
      }

      # Service - Load Balancer 연결 (옵션)
      # app-routing에 정의된 앱만 ALB에 연결
      load_balancer = try(local.app_routing_definitions[app_name], null) != null ? {
        service = {
          target_group_arn = module.alb.target_groups[local.app_routing_definitions[app_name].target_group_key].arn
          container_name   = app_config.container_name
          container_port   = app_config.container_port
        }
      } : null

    }
  }
}

# ECS 서비스 배포 모듈
module "ecs_services" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "6.10.0" # 최신화 2025년 12월 01일

  cluster_name = var.ecs_cluster_name

  # 모든 서비스 정의 통합
  services = local.ecs_services
 create_cloudwatch_log_group = false
  tags = local.tags
  depends_on = [
    module.ecs_cluster
  ]
}
