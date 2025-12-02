# # ECS Service: env-loader
# # 각 앱별로 독립적으로 관리하는 서비스 파일

# locals {
#   # env-loader 서비스 정의
#   ecs_service_env_loader = {
#     "${local.project}-env-loader" = {
#       cpu    = 256
#       memory = 512

#       # Container Definition
#       container_definitions = {
#         "env-loader" = {
#           essential = true
#           image     = "nginx:latest" # 실제 이미지 URI로 변경 필요
#           portMappings = [
#             {
#               name          = "env-loader-80"
#               containerPort = 80
#               protocol      = "tcp"
#             }
#           ]

#           logConfiguration = {
#             logDriver = "awslogs"
#             options = {
#               "awslogs-group"         = "/ecs/${var.ecs_cluster_name}/env-loader"
#               "awslogs-region"        = data.aws_region.current.name
#               "awslogs-stream-prefix" = "ecs"
#             }
#           }

#           environment = []

#           enable_cloudwatch_logging              = true
#           create_cloudwatch_log_group            = true
#           cloudwatch_log_group_retention_in_days = 7
#         }
#       }

#       # Service Configuration
#       desired_count                      = 2
#       deployment_minimum_healthy_percent = 50
#       deployment_maximum_percent         = 200
#       enable_ecs_managed_tags            = true
#       enable_execute_command             = false
#       health_check_grace_period_seconds  = 60

#       deployment_circuit_breaker = {
#         enable   = true
#         rollback = true
#       }

#       # Network Configuration
#       subnet_ids         = module.vpc.private_subnets
#       security_group_ids = [module.ecs_service_sg.security_group_id]
#       assign_public_ip   = false

#       # Launch Type
#       launch_type = "EC2"

#       # Capacity Provider Strategy
#       capacity_provider_strategy = {
#         ec2 = {
#           capacity_provider = "ec2"
#           weight            = 100
#           base              = 1
#         }
#       }

#       # Load Balancer (필요한 경우 주석 해제하고 ALB에 target group 추가)
#       # load_balancer = {
#       #   service = {
#       #     target_group_arn = module.alb.target_groups["env-loader"].arn
#       #     container_name   = "env-loader"
#       #     container_port   = 80
#       #   }
#       # }

#       # IAM Roles
#       create_task_exec_iam_role = true
#       task_exec_iam_role_name   = "${local.project}-env-loader-task-execution-role"

#       create_tasks_iam_role = true
#       tasks_iam_role_name   = "${local.project}-env-loader-task-role"

#       # Task Definition
#       requires_compatibilities = ["EC2"]
#       network_mode            = "awsvpc"
#     }
#   }
# }
