# Argus Timing System - Terraform Variables

# ============ General ============

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "argus"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "deployment_tier" {
  description = <<-EOT
    Deployment tier controlling resource sizing presets.
      "tier1" — Shared SaaS stack (~5k fans, cost-optimized)
      "tier2" — Dedicated event stack (~30k+ fans, high concurrency)
      ""      — No preset; use individual variable values (default, backwards compatible)
    When set, tier presets override: ECS min/max/desired/cpu/memory, RDS class/storage,
    Redis node type, CloudFront price class, and Gunicorn workers. Individual variables
    are still used for anything the tier does not cover.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "tier1", "tier2"], var.deployment_tier)
    error_message = "deployment_tier must be \"\", \"tier1\", or \"tier2\"."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "Domain name for the application (prod only)"
  type        = string
  default     = ""
}

# ============ Networking ============

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnets" {
  description = "Database subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# ============ Database ============

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "argus"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "argus"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"  # Upgrade for prod
}

variable "rds_allocated_storage" {
  description = "RDS initial storage in GB"
  type        = number
  default     = 20
}

variable "rds_max_storage" {
  description = "RDS maximum storage for autoscaling in GB"
  type        = number
  default     = 100
}

# ============ Redis ============

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"  # Upgrade for prod
}

# ============ ECS ============

variable "ecs_cpu" {
  description = "ECS task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "ECS task memory in MB"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 10
}

variable "gunicorn_workers" {
  description = "Number of Gunicorn workers per container"
  type        = number
  default     = 2
}

# ============ Security ============

variable "secret_key" {
  description = "Application secret key for JWT signing"
  type        = string
  sensitive   = true
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS (required for prod)"
  type        = string
  default     = ""
}
