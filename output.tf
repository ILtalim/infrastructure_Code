output "prod_lb_dns" {
  value = aws_lb.prod_lb.dns_name
}

output "prod_domain" {
  value = aws_route53_record.prod_record.fqdn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.main_bucket.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.documents.name
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output "lambda_function_name" {
  value = aws_lambda_function.upload_callback.function_name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.stage.stage_name
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.stage.stage_name}"
}

# variable "region" {
#   default = "us-east-1"
# }