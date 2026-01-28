# Argus Timing System - AWS Infrastructure
# Terraform configuration for production deployment
#
# Architecture:
#   - ECS Fargate for cloud server (auto-scaling)
#   - RDS PostgreSQL for persistent data
#   - ElastiCache Redis for SSE pub/sub + caching
#   - ALB for load balancing with SSL termination
#   - CloudFront for static assets and web app
#   - S3 for web app hosting
#
# Usage:
#   terraform init
#   terraform plan -var-file="prod.tfvars"
#   terraform apply -var-file="prod.tfvars"

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state storage (uncomment for production)
  # backend "s3" {
  #   bucket         = "argus-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "argus-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "argus"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ============ Data Sources ============

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ============ VPC ============

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}"
  cidr = var.vpc_cidr

  azs              = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets  = var.private_subnets
  public_subnets   = var.public_subnets
  database_subnets = var.database_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"  # Cost optimization for non-prod
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # VPC Flow Logs
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# ============ Security Groups ============

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Redis from ECS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-sg"
  }
}

# ============ RDS PostgreSQL ============

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}"
  description = "Database subnet group"
  subnet_ids  = module.vpc.database_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet"
  }
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}"

  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = var.rds_instance_class
  allocated_storage    = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_storage
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = var.environment == "prod"
  publicly_accessible    = false
  deletion_protection    = var.environment == "prod"
  skip_final_snapshot    = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${var.environment}-final" : null

  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  performance_insights_enabled = var.environment == "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }
}

# ============ ElastiCache Redis ============

resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}"
  description = "Redis subnet group"
  subnet_ids  = module.vpc.private_subnets

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-subnet"
  }
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-${var.environment}"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  snapshot_retention_limit = var.environment == "prod" ? 3 : 0
  snapshot_window         = "02:00-03:00"

  tags = {
    Name = "${var.project_name}-${var.environment}-redis"
  }
}

# ============ ECS Cluster ============

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = var.environment == "prod" ? "enabled" : "disabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
  }
}

# ============ ECR Repository ============

resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}/api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============ IAM Roles ============

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# ============ CloudWatch Log Group ============

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

# ============ ECS Task Definition ============

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-${var.environment}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "api"
      image = "${aws_ecr_repository.api.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "DATABASE_URL", value = "postgresql+asyncpg://${var.db_username}:${var.db_password}@${aws_db_instance.main.endpoint}/${var.db_name}" },
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379" },
        { name = "SSE_KEEPALIVE_S", value = "30" },
        { name = "WORKERS", value = tostring(var.gunicorn_workers) },
      ]

      secrets = [
        {
          name      = "SECRET_KEY"
          valueFrom = aws_ssm_parameter.secret_key.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-api-task"
  }
}

# ============ SSM Parameters (Secrets) ============

resource "aws_ssm_parameter" "secret_key" {
  name        = "/${var.project_name}/${var.environment}/secret_key"
  description = "JWT signing secret key"
  type        = "SecureString"
  value       = var.secret_key

  tags = {
    Name = "${var.project_name}-${var.environment}-secret-key"
  }
}

# ============ Application Load Balancer ============

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project_name}-${var.environment}-api"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  # Enable stickiness for SSE connections
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-api-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ============ ECS Service ============

resource "aws_ecs_service" "api" {
  name            = "${var.project_name}-${var.environment}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    ignore_changes = [desired_count]  # Allow auto-scaling to manage
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-api-service"
  }
}

# ============ Auto Scaling ============

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.ecs_max_count
  min_capacity       = var.ecs_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.project_name}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ============ S3 Bucket for Web App ============

resource "aws_s3_bucket" "web" {
  bucket = "${var.project_name}-${var.environment}-web"

  tags = {
    Name = "${var.project_name}-${var.environment}-web"
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "web" {
  bucket = aws_s3_bucket.web.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============ CloudFront Distribution ============

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.project_name}-${var.environment}-web"
  description                       = "OAC for web app S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"  # US, Canada, Europe only
  aliases             = var.environment == "prod" ? [var.domain_name] : []

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.web.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALB-API"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default to S3 (web app)
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.web.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # API routes to ALB
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-API"

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept", "Content-Type"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # SSE endpoint (no caching, keep-alive)
  ordered_cache_behavior {
    path_pattern     = "/api/v1/events/*/stream"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-API"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = false
  }

  # SPA fallback for client-side routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.environment != "prod"
    acm_certificate_arn           = var.environment == "prod" ? var.acm_certificate_arn : null
    ssl_support_method            = var.environment == "prod" ? "sni-only" : null
    minimum_protocol_version      = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cdn"
  }
}

# S3 bucket policy for CloudFront
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.web.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web.arn
          }
        }
      }
    ]
  })
}
