terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

locals {
  name_prefix    = "docmind-${data.aws_caller_identity.current.account_id}"
  bucket_prefix  = "docmind-web"
  api_domain     = "${replace(aws_eip.backend.public_ip, ".", "-")}.sslip.io"
  bedrock_models = toset([var.chat_model, var.embedding_model])
}

resource "random_id" "bucket_suffix" {
  byte_length = 3
}

resource "aws_vpc" "demo" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = { Name = "${local.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend"
  description = "HTTPS origin traffic from CloudFront; HTTP only for ACME certificate issuance."
  vpc_id      = aws_vpc.demo.id

  ingress {
    description = "ACME HTTP-01 validation and HTTPS redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "HTTPS API origin traffic from CloudFront"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-backend" }
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.bucket_prefix}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend-oac"
  description                       = "Private S3 origin for DocMind frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontReadOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })
}

resource "aws_s3_bucket" "backups" {
  bucket = "${local.bucket_prefix}-backup-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-demo-backups"
    status = "Enabled"

    filter { prefix = "postgres/" }
    expiration { days = 30 }
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration { scan_on_push = true }

  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the five most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_iam_role" "backend" {
  name = "${local.name_prefix}-backend-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "backend" {
  name = "${local.name_prefix}-runtime"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeConfiguredBedrockModels"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [for model in local.bedrock_models : "arn:aws:bedrock:${var.aws_region}::foundation-model/${model}"]
      },
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "PullBackendImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = aws_ecr_repository.backend.arn
      },
      {
        Sid      = "WriteDatabaseBackups"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = "${aws_s3_bucket.backups.arn}/postgres/*"
      },
      {
        Sid      = "ListDatabaseBackups"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = aws_s3_bucket.backups.arn
        Condition = {
          StringLike = { "s3:prefix" = ["postgres/*"] }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  name = "${local.name_prefix}-backend-profile"
  role = aws_iam_role.backend.name
}

resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${local.name_prefix}-data" }

  lifecycle { prevent_destroy = true }
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.backend.id]
  iam_instance_profile        = aws_iam_instance_profile.backend.name
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region       = var.aws_region
    data_volume_id   = replace(aws_ebs_volume.data.id, "-", "")
    backup_bucket    = aws_s3_bucket.backups.bucket
    chat_model       = var.chat_model
    embedding_model  = var.embedding_model
    init_sql_base64  = base64encode(file("${path.module}/../../init.sql"))
    caddyfile_base64 = base64encode(file("${path.module}/Caddyfile"))
    compose_base64 = base64encode(templatefile("${path.module}/compose.yaml.tftpl", {
      backend_image = "${aws_ecr_repository.backend.repository_url}:latest"
      api_domain    = local.api_domain
      acme_email    = var.acme_email
    }))
  })
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 12
  }

  depends_on = [aws_iam_role_policy.backend, aws_iam_role_policy_attachment.ssm]

  tags = { Name = "${local.name_prefix}-backend" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.backend.id
}

resource "aws_eip" "backend" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-backend" }
}

resource "aws_eip_association" "backend" {
  allocation_id = aws_eip.backend.id
  instance_id   = aws_instance.backend.id
}

resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${local.name_prefix}-api-origin"
  comment = "Forward auth/content headers and query strings to Spring Boot; do not cache API/SSE responses."

  headers_config {
    header_behavior = "whitelist"
    headers { items = ["Authorization", "Content-Type", "Accept", "Origin", "Last-Event-ID"] }
  }

  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "all" }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "DocMind public demo"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  http_version        = "http2and3"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    domain_name = local.api_domain
    origin_id   = "backend-https"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 120
      origin_keepalive_timeout = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "frontend-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "backend-https"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = false
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_eip_association.backend]
}

resource "aws_cloudfront_function" "spa" {
  name    = "${local.name_prefix}-spa-fallback"
  runtime = "cloudfront-js-2.0"
  comment = "Route client-side application routes to the Vite entry point."
  publish = true
  code    = file("${path.module}/spa-rewrite.js")
}

resource "aws_budgets_budget" "monthly" {
  provider     = aws.us_east_1
  name         = "${local.name_prefix}-monthly-demo"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
