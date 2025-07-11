provider "aws" {
  region = "us-east-1"
  profile = "default"
}

locals {
  name = "amj-raj-system-dev"
  domain_name = "ailawal.ca"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name = "${local.name}-vpc"
  cidr = "10.0.0.0/16"
  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
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
    description = "Port"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [ aws_security_group.prod_lb_sg.id ]
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
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
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


# # Launch Template Configuration for EC2 Instances
# resource "aws_launch_template" "prod_lnch_tmpl" {
#   name_prefix   = "${local.name}-prod_tmpl"
#   image_id      = data.aws_ami.ubuntu.id #"ami-0abcdef123456789"   #
#   instance_type = "t3.large"
#   key_name      = aws_key_pair.public-key.key_name
#   user_data = filebase64("${path.module}/docker_userdata.sh")
#   iam_instance_profile {
#     name = aws_iam_instance_profile.prod_instance_profile.name
#   }
  
#  block_device_mappings {
#     device_name = "/dev/xvdf"  # # Additional EBS volume
#     ebs {
#       volume_size = 100               # Increase root volume to 20GB
#       volume_type = "gp3"            # gp3 is cheaper & faster than gp2
#       delete_on_termination = true
#     }
#  }
#   network_interfaces {
#     security_groups = [aws_security_group.prod_sg.id]
#   }
# }

# #Create an SNS Topic (for hook notifications)
# resource "aws_sns_topic" "lifecycle_topic" {
#   name = "${local.name}-lifecycle-topic"
# }

# # Create an IAM Role for ASG Lifecycle Hook to Use SNS
# resource "aws_iam_role" "asg_lifecycle_role" {
#   name = "${local.name}-asg-lifecycle-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Principal = {
#         Service = "autoscaling.amazonaws.com"
#       },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy" "asg_lifecycle_policy" {
#   name = "asg-lifecycle-policy"
#   role = aws_iam_role.asg_lifecycle_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "sns:Publish",
#           "autoscaling:CompleteLifecycleAction"
#         ],
#         Resource = "*"
#       }
#     ]
#   })
# }

# # Create Auto Scaling Group (ASG) for Production
# resource "aws_autoscaling_group" "prod_asg" {
#   name                      = "${local.name}-prod-asg"
#   max_size                  = 3
#   min_size                  = 1
#   desired_capacity          = 1
#   health_check_type         = "EC2"
#   health_check_grace_period = 300
#   force_delete              = true
#   launch_template {
#     id      = aws_launch_template.prod_lnch_tmpl.id
#     version = "$Latest"
#   }
#   vpc_zone_identifier = module.vpc.private_subnets
#   target_group_arns   = [aws_lb_target_group.team1_prod_target_group.arn]
#   tag {
#     key                 = "Name"
#     value               = "${local.name}-prod-asg"
#     propagate_at_launch = true
#   }
# }

# # Lifecycle Hook (Separate Resource)
# resource "aws_autoscaling_lifecycle_hook" "wait_for_app_ready" {
#   name                    = "wait-for-app-ready"
#   autoscaling_group_name = aws_autoscaling_group.prod_asg.name
#   lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
#   heartbeat_timeout       = 7200
#   default_result          = "CONTINUE"
#   notification_target_arn = aws_sns_topic.lifecycle_topic.arn
#   role_arn                = aws_iam_role.asg_lifecycle_role.arn
# }

# # Auto Scaling Policy for Dynamic Scaling
# resource "aws_autoscaling_policy" "prod_team1_asg_policy" {
#   autoscaling_group_name = aws_autoscaling_group.prod_asg.name
#   name                   = "${local.name}-prod-team1-asg-policy"
#   adjustment_type        = "ChangeInCapacity"
#   policy_type            = "TargetTrackingScaling"

#   target_tracking_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ASGAverageCPUUtilization"
#     }
#     target_value = 50.0
#   }
# }

#creating and attaching an IAM role with SSM permissions to the instance.
resource "aws_iam_role" "prodec2_ssm_role" {
  name = "${local.name}-ssm-role"
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

#Attach the AmazonSSMManagedInstanceCore policy
# — required for Session Manager and SSM Agent functionality.
resource "aws_iam_role_policy_attachment" "prodec2_ssm_attachment" {
  role       = aws_iam_role.prodec2_ssm_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
#Attaching AdministratorAccess (this grants full access to AWS resources)
resource "aws_iam_role_policy_attachment" "prodec2-admin_access_attachment" {
  role       = aws_iam_role.prodec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# create instance profiles- as EC2 instances can’t assume roles directly
resource "aws_iam_instance_profile" "prodec2_ssm_profile" {
  name = "${local.name}-ssm-instance-profile"
  role = aws_iam_role.prodec2_ssm_role.id
}

# Create a security group
resource "aws_security_group" "prodec2_sg" {
  name        = "${local.name}-prodec2_sg"
  description = "Allow prodec2 without ssh"
  vpc_id      = module.vpc.vpc_id # Attach to the created VPC
  # Inbound rule for prodec2 web interface
  ingress {
    description = "Allow HTTP traffic to prodec2"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups  = [aws_security_group.prod_lb_sg.id] # Replace cidr_blocks # Open to the world (can restrict for security)
  }
  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Launch an EC2 instance for prodec2
resource "aws_instance" "prodec2" {
  ami                         = data.aws_ami.ubuntu.id       # AMI ID passed as a variable (e.g., RHEL)
  instance_type               = "t2.medium"                        # Instance type (e.g., t3.medium)
  subnet_id                   = module.vpc.public_subnets[0]    # Use first available subnet
  vpc_security_group_ids      = [aws_security_group.prodec2_sg.id] # Attach security group       # Use the created key pair
  associate_public_ip_address = true                               # Required for SSH and browser access
  iam_instance_profile        = aws_iam_instance_profile.prodec2_ssm_profile.name
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = true
  }
  # User data script to install prodec2 and required tools
  user_data = templatefile("./docker_userdata.sh", {
    region = var.region
  })
  metadata_options {
    http_tokens = "required"
  }
  # Tag the instance for easy identification
  tags = {
    Name = "${local.name}-prodec2-server"
  }
}

#creating security group for loadbalancer
resource "aws_security_group" "prod_lb_sg" {
  name = "${local.name}-prod-lb-sg"
  description = "Allow inbound traffic from port 80 and 443"
  vpc_id = module.vpc.vpc_id
  ingress {
    description      = "https access"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${local.name}-prod-lb-sg"
  }
}

# create application load balancer for prod
resource "aws_lb" "prod_lb" {
  name               = "${local.name}-prod-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_lb_sg.id]
  subnets            = module.vpc.public_subnets
  enable_deletion_protection = false
  tags   = {
    Name = "${local.name}-prod-lb"
  }
}

# create target group for prod
resource "aws_lb_target_group" "prod_target_group" {
  name        = "${local.name}-prod-tg"
  target_type = "instance"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    matcher             = "200" 
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "prodec2_attachment" {
  target_group_arn = aws_lb_target_group.prod_target_group.arn
  target_id        = aws_instance.prodec2.id
  port             = 3000
}


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
  load_balancer_arn  = aws_lb.prod_lb.arn
  port               = 443
  protocol           = "HTTPS"
  ssl_policy         = "ELBSecurityPolicy-2016-08"
  certificate_arn    = aws_acm_certificate.acm-cert.arn
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

resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = "amj-rag-system-dev-lambda-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.id
  key    = "lambda/upload_handler.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = filemd5(data.archive_file.lambda_zip.output_path)
}

# DynamoDB Table
resource "aws_dynamodb_table" "documents" {
  name         = "amj-rag-system-dev-documents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "document_id"

  attribute {
    name = "document_id"
    type = "S"
  }
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

resource "aws_sns_topic_subscription" "email_sub_2" {
  topic_arn = aws_sns_topic.upload_notifications.arn
  protocol  = "email"
  endpoint  = "fazilatur.rahman@talim.ca"
}


#Add ingress rule to EC2 SG to allow Lambda SG
resource "aws_security_group_rule" "allow_lambda_to_ec2" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.prodec2_sg.id
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
  name = "amj-rag-system-dev-lambda-policy"
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
      }
    ]
  })
}

#Security Group for Lambda
resource "aws_security_group" "lambda_sg" {
  name        = "${local.name}-lambda-sg"
  description = "Allow Lambda outbound to EC2 on port 8000"
  vpc_id      = module.vpc.vpc_id

  # Allow Lambda to send requests to EC2 on port 8000
  egress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [module.vpc.private_subnets_cidr_blocks[0]]  # Or specify EC2 subnet CIDR
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_custom_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_custom_policy.arn
}

# Create Lambda Function
resource "aws_lambda_function" "upload_callback" {
  function_name = "amj-rag-system-dev-upload-handler"
  s3_bucket     = aws_s3_bucket.lambda_bucket.id
  s3_key        = aws_s3_bucket_object.lambda_zip.key
  handler       = "upload_handler.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn

   vpc_config {
    subnet_ids         = module.vpc.private_subnets  # Use private subnet IDs here
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DDB_TABLE_NAME = aws_dynamodb_table.documents.name
      SNS_TOPIC_ARN  = aws_sns_topic.upload_notifications.arn
    }
    
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_exec,
    aws_iam_role_policy_attachment.lambda_custom_attach
  ]
}


# S3 Bucket and Trigger
resource "aws_s3_bucket" "upload_bucket" {
  bucket        = "amj-rag-system-dev-upload-bucket"
  force_destroy = true
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_callback.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn
}

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.upload_callback.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/" # Optional: restrict to /uploads/
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
