terraform {
  backend "s3" {
    bucket         = "amjrag-tf-state-dev"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "amjrag-tf-locks"
    encrypt        = true
  }
}


provider "aws" {
  region = "us-east-1"
  # profile = "default"
}

locals {
  name        = "amj-raj-system-dev"
  domain_name = "ailawal.ca"
}

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "${local.name}-vpc"
  cidr               = "10.0.0.0/16"
  azs                = ["us-east-1a", "us-east-1b"]
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets    = ["10.0.3.0/24", "10.0.4.0/24"]
  single_nat_gateway = true
  enable_nat_gateway = true
  tags = {
    Name = local.name
  }
}

resource "aws_iam_role" "bastion_ssm_role" {
  name = "${local.name}-bastion-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${local.name}-bastion-instance-profile"
  role = aws_iam_role.bastion_ssm_role.name
}

resource "aws_security_group" "bastion_sg" {
  name        = "${local.name}-bastion-sg"
  description = "Allow egress for SSM access"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${local.name}-bastion-sg"
  }
}

# Data source to get the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "bastion_lt" {
  name_prefix   = "${local.name}-bastion-lt"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  user_data = base64encode(templatefile("./bastion_userdata.sh", {
    private_keypair_path = tls_private_key.key.private_key_pem,
  }))
  iam_instance_profile { name = aws_iam_instance_profile.bastion_profile.name }
  lifecycle { create_before_destroy = true }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.bastion_sg.id]
  }
  tags = {
    Name = "${local.name}-bastion-lt"
  }
}

resource "aws_autoscaling_group" "bastion_asg" {
  name                = "${local.name}-bastion-asg"
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = module.vpc.public_subnets
  launch_template {
    id      = aws_launch_template.bastion_lt.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${local.name}-bastion-asg"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Creating the Security Group for Production Environment
resource "aws_security_group" "prod_sg" {
  name        = "${local.name}-prod-sg"
  description = "Security group for prod-env"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description     = "Port"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.prod_lb_sg.id]
  }
  # SSH Access - Only allow traffic from the Bastion security group
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id] # Allow SSH only from Bastion SG
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${local.name}-prod-sg"
  }
}


# creating keypair RSA key
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "key" {
  content         = tls_private_key.key.private_key_pem
  filename        = "${local.name}-key.pem"
  file_permission = 400
}
# creating public-key
resource "aws_key_pair" "public-key" {
  key_name   = "${local.name}-public-key"
  public_key = tls_private_key.key.public_key_openssh
}

resource "aws_iam_role" "prod_ssm_role" {
  name = "${local.name}-prod-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prod_ssm_attach" {
  role       = aws_iam_role.prod_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "prod_instance_profile" {
  name = "${local.name}-prod-instance-profile"
  role = aws_iam_role.prod_ssm_role.name
}

# Launch Template Configuration for EC2 Instances
resource "aws_launch_template" "prod_lnch_tmpl" {
  name_prefix   = "${local.name}-prod-tmpl"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.medium"
  key_name      = aws_key_pair.public-key.key_name
  user_data     = base64encode(file("./script.sh"))
  block_device_mappings {
    device_name = "/dev/sda1" # Typical root device name for Ubuntu AMIs
    ebs {
      volume_size = 100   # New size in GB (default is usually 8GB)
      volume_type = "gp3" # Recommended modern volume type
      encrypted   = true  # Good practice to enable encryption
    }
  }
  monitoring {
    enabled = true
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.prod_instance_profile.name
  }
  network_interfaces {
    security_groups             = [aws_security_group.prod_sg.id]
    associate_public_ip_address = true
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}


# Create Auto Scaling Group (ASG) for Production
resource "aws_autoscaling_group" "prod_asg" {
  name                      = "${local.name}-prod-asg"
  max_size                  = 3
  min_size                  = 2
  desired_capacity          = 2
  health_check_grace_period = 120
  health_check_type         = "EC2"
  force_delete              = true
  vpc_zone_identifier       = [module.vpc.private_subnets[0], module.vpc.private_subnets[1]]
  target_group_arns         = [aws_lb_target_group.prod_target_group.arn]
  launch_template {
    id      = aws_launch_template.prod_lnch_tmpl.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling" # Default (alternatives: "RollingWithAdditionalBatch")
    preferences {
      min_healthy_percentage = 90  # Keep 90% healthy during refresh
      instance_warmup        = 120 # Seconds to wait for new instances
    }
  }
  tag {
    key                 = "Name"
    value               = "${local.name}-prod-asg"
    propagate_at_launch = true
  }
}


# # Auto Scaling Policy for Dynamic Scaling
resource "aws_autoscaling_policy" "prod_asg_policy" {
  autoscaling_group_name = aws_autoscaling_group.prod_asg.name
  name                   = "${local.name}-prod-team1-asg-policy"
  adjustment_type        = "ChangeInCapacity"
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}


#creating security group for loadbalancer
resource "aws_security_group" "prod_lb_sg" {
  name        = "${local.name}-prod-lb-sg"
  description = "Allow inbound traffic from port 80 and 443"
  vpc_id      = module.vpc.vpc_id
  ingress {
    description = "https access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "http access"
    from_port   = 80
    to_port     = 80
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
    Name = "${local.name}-prod-lb-sg"
  }
}

# create application load balancer for prod
resource "aws_lb" "prod_lb" {
  name                       = "${local.name}-prod-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.prod_lb_sg.id]
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false
  tags = {
    Name = "${local.name}-prod-lb"
  }
}

# create target group for prod
resource "aws_lb_target_group" "prod_target_group" {
  name        = "${local.name}-prod-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    path                = "/"
  }
  tags = {
    Name = "${local.name}-prod-tg"
  }
}

# resource "aws_lb_target_group_attachment" "prod_attachment" {
#   target_group_arn = aws_lb_target_group.prod_target_group.arn
#   target_id        = aws_instance.prod.id
#   port             = 3000
# }


# create a listener on port 80 with redirect action
resource "aws_lb_listener" "prod_http_listener" {
  load_balancer_arn = aws_lb.prod_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# create a listener on port 443 with forward action
resource "aws_lb_listener" "prod_https_listener" {
  load_balancer_arn = aws_lb.prod_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.acm-cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_target_group.arn
  }
}

# get details about a route 53 hosted zone
data "aws_route53_zone" "hosted_zone" {
  name         = local.domain_name
  private_zone = false
}


# create a record set for production
resource "aws_route53_record" "prod_record" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "prodtest.${local.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.prod_lb.dns_name
    zone_id                = aws_lb.prod_lb.zone_id
    evaluate_target_health = true
  }
}

# Create ACM certificate with DNS validation
resource "aws_acm_certificate" "acm-cert" {
  domain_name               = local.domain_name
  subject_alternative_names = ["*.${local.domain_name}"]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name}-acm-cert"
  }
}

# Fetch DNS Validation Records for ACM Certificate
resource "aws_route53_record" "acm_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.acm-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  # Create DNS Validation Record for ACM Certificate
  zone_id         = data.aws_route53_zone.hosted_zone.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  depends_on      = [aws_acm_certificate.acm-cert]
}

# Validate the ACM Certificate after DNS Record Creation
resource "aws_acm_certificate_validation" "team2_cert_validation" {
  certificate_arn         = aws_acm_certificate.acm-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation_record : record.fqdn]
  depends_on              = [aws_acm_certificate.acm-cert]
}



# Lambda Zip and Bucket
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# S3 Bucket Configuration
resource "aws_s3_bucket" "main_bucket" {
  bucket = "${local.name}-main-bucket"

  tags = {
    Name        = "${local.name}-main-bucket"
    Environment = "dev"
  }

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main_bucket" {
  bucket = aws_s3_bucket.main_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

  
  # Block public access (important security setting)
  resource "aws_s3_bucket_public_access_block" "main_bucket" {
    bucket                  = aws_s3_bucket.main_bucket.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

 
  # Enable object lock for compliance if needed
  # object_lock_configuration {
  #   object_lock_enabled = "Enabled"
  # }

 

# Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "main_bucket" {
  bucket = aws_s3_bucket.main_bucket.id

  rule {
  id     = "expire_old_objects"
  status = "Enabled"

  filter {}  # This means apply to all objects

  expiration {
    days = 30
  }
}

  # Add lifecycle rule for old versions if needed
  # rule {
  #   id     = "version-transition"
  #   status = "Enabled"
  #
  #   noncurrent_version_transition {
  #     days          = 30
  #     storage_class = "STANDARD_IA"
  #   }
  #
  #   noncurrent_version_expiration {
  #     days = 90
  #   }
  # }
}



resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.main_bucket.id
  key    = "lambda/upload_handler.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path)
}

# DynamoDB Table
resource "aws_dynamodb_table" "documents" {
  name         = "${local.name}-DynamoDB-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "document_id"

  attribute {
    name = "document_id"
    type = "S"
  }

 attribute {
    name = "upload_time"
    type = "N"  # Number (timestamp)
  }

  # Then define indexes that reference these attributes
  global_secondary_index {
    name            = "UploadTimeIndex"
    hash_key        = "document_id"  # Partition key
    range_key       = "upload_time"  # Sort key
    projection_type = "ALL"          # Project all attributes
    write_capacity  = 1              # Required for PAY_PER_REQUEST
    read_capacity   = 1              # Required for PAY_PER_REQUEST
  }

  ttl {
    attribute_name = "expiry_time"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }
}

# Add CloudFront cache invalidation resource
resource "aws_cloudfront_cache_policy" "custom_caching" {
  name        = "${local.name}-custom-caching"
  comment     = "Custom caching policy for ${local.name}"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# outputs for important resources
output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
}

# output "lambda_function_name" {
#   value = aws_lambda_function.upload_callback.function_name
# }

# output "dynamodb_table_name" {
#   value = aws_dynamodb_table.documents.name
# }

output "s3_upload_bucket_name" {
  value = aws_s3_bucket.main_bucket.bucket
}


# SNS Topic and Subscription
resource "aws_sns_topic" "upload_notifications" {
  name = "amj-rag-system-dev-upload-topic"
}

# IAM Role for Lambda
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.upload_notifications.arn
  protocol  = "email"
  endpoint  = "lawalishaq000123@gmail.com" # Replace with your real email
}

resource "aws_sns_topic_subscription" "email_sub_1" {
  topic_arn = aws_sns_topic.upload_notifications.arn
  protocol  = "email"
  endpoint  = "isiaka.lawal@talim.ca"
}

# resource "aws_sns_topic_subscription" "email_sub_2" {
#   topic_arn = aws_sns_topic.upload_notifications.arn
#   protocol  = "email"
#   endpoint  = "fazilatur.rahman@talim.ca"
# }


# Allow EC2 to receive requests from Lambda
resource "aws_security_group_rule" "allow_lambda_to_ec2" {
  type                     = "ingress"
  from_port                = 8000 # Django server port
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.prod_sg.id
  source_security_group_id = aws_security_group.lambda_sg.id
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "amj-rag-system-dev-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_custom_policy" {
  name = "${local.name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["dynamodb:PutItem"],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.documents.arn
      },
      {
        Action   = "sns:Publish",
        Effect   = "Allow",
        Resource = aws_sns_topic.upload_notifications.arn
      },
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.main_bucket.arn}/*"
      },
      {
        Action = ["ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

#Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  name        = "${local.name}-lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # lifecycle {
  #   prevent_destroy = true # For production environments
  # }
}


# Allow EC2 to receive requests from Lambda
# resource "aws_security_group_rule" "allow_lambda_to_ec2" {
#   type                     = "ingress"
#   from_port                = 8000  # Django server port
#   to_port                  = 8000
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.prod_sg.id
#   source_security_group_id = aws_security_group.lambda_sg.id
# }

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.upload_callback.function_name}"
  retention_in_days = 14
}

# Create Lambda Function
resource "aws_lambda_function" "upload_callback" {
  function_name = "${local.name}-upload-handler"
  s3_bucket     = aws_s3_bucket.main_bucket.id
  s3_key        = "lambda/upload_handler.zip"
  handler       = "upload_handler.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 30  # Increased from default 3 seconds
  memory_size   = 512 # Increased from default 128MB

  vpc_config {
    subnet_ids         = module.vpc.private_subnets # Use private subnet IDs here
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DDB_TABLE_NAME          = aws_dynamodb_table.documents.name
      SNS_TOPIC_ARN           = aws_sns_topic.upload_notifications.arn
      DJANGO_CALLBACK_URL = "https://${aws_lb.prod_lb.dns_name}/api/process" # Use ALB DNS instead of ASG
      CF_CDN_DOMAIN           = aws_cloudfront_distribution.s3_distribution.domain_name
      CF_KEY_PAIR_ID          = aws_cloudfront_public_key.this.id
      PRIVATE_KEY_SECRET_NAME = aws_secretsmanager_secret.cloudfront_private_key.name
    }

  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_exec,
    aws_iam_role_policy_attachment.lambda_custom_attach,
    aws_iam_role_policy_attachment.lambda_vpc_access
  ]
}


# Allow S3 to invoke Lambda function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_callback.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main_bucket.arn
}

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.main_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.upload_callback.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/" # Optional: restrict to /uploads/
    filter_suffix       = ".pdf"     # Optional: only trigger for PDF files
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Add lifecycle policy to S3 bucket
resource "aws_s3_bucket_lifecycle_configuration" "upload_bucket" {
  bucket = aws_s3_bucket.main_bucket.id

  rule {
    id     = "auto-delete-incomplete"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# 🔐 Define the secret resource
resource "aws_secretsmanager_secret" "env_dev" {
  name                    = "env/dev"
  description             = "Dev environment variables"
  recovery_window_in_days = 7 # Optional: Set recovery window for secret deletion

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

# 💾 Upload the rendered template as the secret value
resource "aws_secretsmanager_secret_version" "env_dev_version" {
  secret_id     = aws_secretsmanager_secret.env_dev.id
  secret_string = data.template_file.env_dev.rendered
}

# 🧪 Generate the .env.dev content from your .env.dev.tpl
data "template_file" "env_dev" {
  template = file("${path.module}/.env.dev.tpl")
  vars = {
    AWS_S3_BUCKET                  = aws_s3_bucket.main_bucket.bucket
    AWS_DYNAMODB_TABLE_NAME       = aws_dynamodb_table.documents.name
    AWS_CDN_BASE_URL              = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
    AWS_API_GATEWAY_REST_API_ID   = aws_api_gateway_rest_api.api.id
    AWS_API_GATEWAY_STAGE_NAME    = aws_api_gateway_stage.stage.stage_name
  }
}



output "env_dev_secret_arn" {
  value     = aws_secretsmanager_secret.env_dev.arn
  sensitive = true
}


# Add KMS key for secrets encryption (if not already present)
resource "aws_kms_key" "secrets" {
  description             = "KMS key for CloudFront private key and other secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.main_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.main_bucket.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${local.name} upload bucket"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-${aws_s3_bucket.main_bucket.id}"
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    origin_request_policy_id   = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # CORS-S3Origin
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy

    # forwarded_values {
    #   query_string = false
    #   cookies {
    #     forward = "none"
    #   }
    # }

    viewer_protocol_policy = "redirect-to-https"
    # min_ttl                = 0
    # default_ttl            = 3600
    # max_ttl                = 86400

    # Add CloudFront key group for signed URLs
    trusted_key_groups = [aws_cloudfront_key_group.this.id]
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }


  tags = {
    Name = "${local.name}-cdn"
  }
}

# CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${local.name} main bucket"
}

# S3 bucket policy to allow CloudFront access
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
  }
  
  depends_on = [aws_s3_bucket.main_bucket]
  
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.main_bucket.arn}/*"]
  
  principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda_exec_role.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.main_bucket.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

# Fully Automated CloudFront Key Pair Setup
resource "tls_private_key" "cloudfront_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_cloudfront_public_key" "this" {
  comment     = "${local.name}-public-key"
  encoded_key = tls_private_key.cloudfront_key.public_key_pem
  name        = "${local.name}-cf-key"
lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_key_group" "this" {
  comment = "${local.name}-key-group"
  items   = [aws_cloudfront_public_key.this.id]
  name    = "${local.name}-cf-key-group"
# lifecycle {
#     prevent_destroy = true # Add this to prevent accidental deletion
#   }
}

# Automated Secret Management for CloudFront Private Key
resource "aws_secretsmanager_secret" "cloudfront_private_key" {
  name        = "lambda/cdn/private_key2025"
  description = "CloudFront private key for signed URLs"
  kms_key_id  = aws_kms_key.secrets.arn # Add if you have KMS

  depends_on = [aws_kms_key.secrets]

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "aws_secretsmanager_secret_version" "cloudfront_private_key" {
  secret_id     = aws_secretsmanager_secret.cloudfront_private_key.id
  secret_string = tls_private_key.cloudfront_key.private_key_pem
}

#  Optional: Local backup of keys
resource "local_file" "cloudfront_private_key_backup" {
  filename        = "${path.module}/cloudfront_private_key.pem"
  content         = tls_private_key.cloudfront_key.private_key_pem
  file_permission = "0400"
}

resource "local_file" "cloudfront_public_key_backup" {
  filename        = "${path.module}/cloudfront_public_key.pem"
  content         = tls_private_key.cloudfront_key.public_key_pem
  file_permission = "0400"
}

# Lambda IAM Policy for Secret Access
resource "aws_iam_role_policy" "lambda_secrets_access" {
  name = "${local.name}-lambda-secrets-access"
  role = aws_iam_role.lambda_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = ["secretsmanager:GetSecretValue"],
      Effect   = "Allow",
      Resource = aws_secretsmanager_secret.cloudfront_private_key.arn
    }]
  })
}

# output "cloudfront_distribution_domain" {
#   value = aws_cloudfront_distribution.s3_distribution.domain_name
# }

output "cloudfront_key_group_id" {
  value = aws_cloudfront_key_group.this.id
}

# monitoring and alerts
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "This alarm monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.upload_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.upload_callback.function_name
  }
}

# S3 Endpoint (Gateway type - no security group needed)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# DynamoDB Endpoint (Gateway type)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# Interface endpoints (for services needing security groups)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids = [aws_security_group.new_lambda_sg.id]
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc.private_subnets
  security_group_ids = [aws_security_group.new_lambda_sg.id]
}


resource "aws_security_group" "new_lambda_sg" {
  name        = "${local.name}-lambda-sg-v2"
  description = "Replacement security group for lambda"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${local.name}-rest-api"
  description = "Public API forwarding to Django backend via ALB"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "https://${aws_lb.prod_lb.dns_name}/{proxy}" # Django backend EC2
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode(aws_api_gateway_integration.proxy_integration))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "dev"
}

resource "aws_iam_role_policy_attachment" "cognito_access" {
  role       = aws_iam_role.prod_ssm_role.name
  policy_arn = aws_iam_policy.cognito_access.arn
}

resource "aws_iam_policy" "cognito_access" {
  name   = "cognito-access-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:ListUsers"
        ]
        Resource = "*"
      }
    ]
  })
}

# resource "aws_security_group" "lambda_sg" {
#   name        = "${local.name}-lambda-sg"
#   description = "Security group for Lambda function (to be deleted)"
#   vpc_id      = module.vpc.vpc_id

#   lifecycle {
#     ignore_changes = [name] # Prevent recreation
#   }
# }

# variable "region" {
#   default = "us-east-1"
# }