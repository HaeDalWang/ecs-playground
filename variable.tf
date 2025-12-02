variable "domain_name" {
  description = "The domain name for the project"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "ecs-cluster"
}

variable "ecs_instance_type" {
  description = "EC2 instance type for ECS cluster"
  type        = string
  default     = "t3.medium"
}

variable "ecs_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "ecs_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}

variable "ecs_desired_size" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "container_cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory for the container in MB"
  type        = number
  default     = 512
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "app"
}