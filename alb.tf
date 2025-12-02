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

# ALB 설정을 동적으로 생성하기 위한 로컬 변수
locals {
  # 앱 라우팅 목록 (app-routing 디렉토리에서 읽기)
  alb_routing_apps = [
    "fastapi-logger"
  ]

  # 각 앱의 라우팅 정의 파일 읽기 및 파싱
  alb_app_routing_definitions = {
    for app in local.alb_routing_apps : app => jsondecode(file("${path.module}/app-routing/${app}.json"))
  }

  # 라우팅이 정의된 앱들 (ALB를 사용하는 앱들)
  alb_lb_enabled_apps = local.alb_app_routing_definitions

  # app-definitions 읽기 (container_port 등이 필요)
  # ecs-services.tf와 동일한 방식으로 읽기
  alb_apps = [
    "fastapi-logger"
  ]
  
  alb_app_definitions = {
    for app in local.alb_apps : app => jsondecode(file("${path.module}/app-definitions/${app}.json"))
  }

  # 타겟 그룹을 생성
  dynamic_target_groups = {
    for app_name, routing_config in local.alb_lb_enabled_apps :
    routing_config.target_group_key => {
      name                 = "${local.project}-${app_name}-tg"
      backend_protocol     = "HTTP"
      # app-definitions에서 container_port 가져오기
      backend_port         = local.alb_app_definitions[app_name].container_port
      target_type          = "ip"
      deregistration_delay = 30

      health_check = try(routing_config.health_check, null) != null ? {
        enabled             = try(routing_config.health_check.enabled, true)
        healthy_threshold   = try(routing_config.health_check.healthy_threshold, 2)
        unhealthy_threshold = try(routing_config.health_check.unhealthy_threshold, 2)
        timeout             = try(routing_config.health_check.timeout, 5)
        interval            = try(routing_config.health_check.interval, 30)
        path                = try(routing_config.health_check.path, "/")
        protocol            = try(routing_config.health_check.protocol, "HTTP")
        matcher             = try(routing_config.health_check.matcher, "200")
      } : {
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

  # 동적 리스너 규칙 생성
  # path_patterns 또는 host_header가 있는 앱만 규칙 생성 (조건이 필수이므로)
  dynamic_listener_rules = {
    # idx: 현재 인덱스 (0부터 시작), app_name: 앱 이름 (예: "fastapi-logger")
    # path_patterns 또는 host_header가 있는 경우만 규칙 생성
    for idx, app_name in keys(local.alb_lb_enabled_apps) :
      "${app_name}-rule" => {
      # 우선순위 설정: ALB는 낮은 숫자부터 순서대로 규칙을 평가
      # - JSON에 priority가 명시되어 있으면 그 값 사용
      # - 없으면 자동 계산: 100 + (인덱스 * 10) = 100, 110, 120, ...
      # 즉, 먼저 등록된 앱이 우선순위가 높음 참고
      priority = try(local.alb_lb_enabled_apps[app_name].priority, 100 + (idx * 10))
      
      # 조건 설정: 이 규칙이 적용될 조건
      # host_header와 path_pattern을 모두 지원
      conditions = concat(
        # host_header 조건 (도메인 기반 라우팅)
        try(local.alb_lb_enabled_apps[app_name].host_header, null) != null && length(try(local.alb_lb_enabled_apps[app_name].host_header, [])) > 0 ? [{
          host_header = {
            values = local.alb_lb_enabled_apps[app_name].host_header
          }
        }] : [],
        # path_pattern 조건 (경로 기반 라우팅)
        try(local.alb_lb_enabled_apps[app_name].path_patterns, null) != null && length(try(local.alb_lb_enabled_apps[app_name].path_patterns, [])) > 0 ? [{
          path_pattern = {
            values = local.alb_lb_enabled_apps[app_name].path_patterns
          }
        }] : []
      )
      
      # 액션 설정: 조건이 만족되었을 때 수행할 동작
      actions = [{
        forward = {
          # 타겟 그룹 키: 요청을 전달할 타겟 그룹 지정
          # target_group_key는 JSON의 "target_group_key" 값 (예: "fastapi-logger")
          # 이 키로 dynamic_target_groups에서 해당 타겟 그룹을 찾음
          target_group_key = local.alb_lb_enabled_apps[app_name].target_group_key
        }
      }]
    } if try(local.alb_lb_enabled_apps[app_name].path_patterns, null) != null || try(local.alb_lb_enabled_apps[app_name].host_header, null) != null
  }

  # 기본 타겟 그룹 (필요한 경우)
  default_target_group = {
    ecs = {
      name                 = "${local.project}-default-tg"
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
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    # HTTPS Listener - 동적으로 생성된 리스너 규칙 사용
    https = {
      port     = 443
      protocol = "HTTPS"
      certificate_arn = aws_acm_certificate.project.arn
      
      # 기본 액션: rules가 매칭되지 않을 때 사용 (필수)
      # forward를 사용하여 기본 타겟 그룹으로 요청 전달
      forward = {
        target_group_key = "ecs"
      }
      
      # 동적으로 생성된 리스너 규칙
      # 기본 동작은 위의 forward로 처리됨 (rules가 매칭되지 않을 때)
      rules = local.dynamic_listener_rules
    }
  }

  # 동적으로 생성된 타겟 그룹 + 기본 타겟 그룹
  target_groups = merge(
    local.dynamic_target_groups,
    local.default_target_group
  )

  tags = merge(
    local.tags,
    {
      Name = "${local.project}-alb"
    }
  )
}

