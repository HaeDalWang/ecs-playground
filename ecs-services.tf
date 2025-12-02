# ECS Services - 모든 서비스 정의를 통합
# 각 서비스는 ecs-service-*.tf 파일에서 정의되고 여기서 통합됨

# # 모든 서비스 정의 통합
# locals {
#   ecs_services = merge(
#     try(local.ecs_service_env_loader, {}),
#     # 다른 서비스 파일에서 정의된 서비스들을 여기에 추가
#     # 예: try(local.ecs_service_app2, {}),
#     # 예: try(local.ecs_service_app3, {})
#   )
# }

# # ECS 서비스 모듈 - 모든 서비스를 기존 클러스터에 배포
# # 참고: 클러스터는 이미 ecs-cluster.tf에서 생성됨
# module "ecs_services" {
#   source  = "terraform-aws-modules/ecs/aws"
#   version = "6.10.0" # 최신화 2025년 12월 01일

#   cluster_name = var.ecs_cluster_name

#   # 모든 서비스 정의 통합
#   services = local.ecs_services

#   tags = local.tags

#   depends_on = [
#     module.ecs_cluster
#   ]
# }

