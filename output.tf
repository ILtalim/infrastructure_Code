output "prod_lb_dns" {
  value = aws_lb.prod_lb.dns_name
}

output "prod_domain" {
  value = aws_route53_record.prod_record.fqdn
}
