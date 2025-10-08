# Request ACM certificate (DNS validation)
resource "aws_acm_certificate" "sock" {
  domain_name       = "sock.blessedc.org"
  validation_method = "DNS"

  tags = {
    Project     = "sockshop"
    Environment = "prod"
  }
}

# Create DNS validation records in your Route53 hosted zone
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.sock.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.sock-shop.zone_id
}

# Wait for ACM to validate certificate automatically
resource "aws_acm_certificate_validation" "sock" {
  certificate_arn         = aws_acm_certificate.sock.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Output certificate ARN
output "acm_certificate_arn" {
  value = aws_acm_certificate.sock.arn
}
