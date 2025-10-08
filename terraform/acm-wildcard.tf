resource "aws_acm_certificate" "sock_wildcard" {
  domain_name               = "*.sock.blessedc.org"
  subject_alternative_names = ["sock.blessedc.org"]
  validation_method         = "DNS"

  tags = {
    Project     = "sockshop"
    Environment = "prod"
  }
}

resource "aws_route53_record" "sock_wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.sock_wildcard.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.sock-shop.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "sock_wildcard_validation" {
  certificate_arn         = aws_acm_certificate.sock_wildcard.arn
  validation_record_fqdns = values(aws_route53_record.sock_wildcard_validation)[*].fqdn
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate.sock_wildcard.arn
  description = "ARN of the wildcard SSL certificate for *.sock.blessedc.org"
}
