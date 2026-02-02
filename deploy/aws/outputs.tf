# Argus Timing System - Terraform Outputs

# ============ Networking ============

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# ============ Database ============

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

# ============ Redis ============

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = aws_elasticache_cluster.main.port
}

# ============ ECS ============

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.api.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for API container"
  value       = aws_ecr_repository.api.repository_url
}

# ============ Load Balancer ============

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer zone ID (for Route53)"
  value       = aws_lb.main.zone_id
}

# ============ CloudFront ============

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.web.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.web.domain_name
}

# ============ S3 ============

output "web_bucket_name" {
  description = "S3 bucket name for web app"
  value       = aws_s3_bucket.web.id
}

output "web_bucket_arn" {
  description = "S3 bucket ARN for web app"
  value       = aws_s3_bucket.web.arn
}

# ============ Deployment Tier ============

output "deployment_tier" {
  description = "Active deployment tier (empty string = no preset, using individual variables)"
  value       = var.deployment_tier
}

output "effective_sizing" {
  description = "Resolved resource sizing (from tier preset or individual variables)"
  value = {
    ecs_cpu           = local.effective_ecs_cpu
    ecs_memory        = local.effective_ecs_memory
    ecs_min_count     = local.effective_ecs_min_count
    ecs_max_count     = local.effective_ecs_max_count
    ecs_desired_count = local.effective_ecs_desired_count
    rds_instance_class = local.effective_rds_instance_class
    rds_storage        = "${local.effective_rds_allocated_storage}–${local.effective_rds_max_storage} GB"
    redis_node_type    = local.effective_redis_node_type
    cf_price_class     = local.effective_cf_price_class
    gunicorn_workers   = local.effective_gunicorn_workers
  }
}

# ============ URLs ============

output "api_url" {
  description = "API URL (via ALB)"
  value       = "https://${aws_lb.main.dns_name}/api/v1"
}

output "web_url" {
  description = "Web app URL (via CloudFront)"
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
}

# ============ Deployment Commands ============

output "deploy_instructions" {
  description = "Instructions for deploying updates"
  value       = <<-EOT

    # Build and push API container:
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.api.repository_url}
    docker build -t ${aws_ecr_repository.api.repository_url}:latest ./cloud
    docker push ${aws_ecr_repository.api.repository_url}:latest
    aws ecs update-service --cluster ${aws_ecs_cluster.main.name} --service ${aws_ecs_service.api.name} --force-new-deployment

    # Deploy web app:
    cd web && npm run build
    aws s3 sync dist/ s3://${aws_s3_bucket.web.id} --delete
    aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.web.id} --paths "/*"

  EOT
}
