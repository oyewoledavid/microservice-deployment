# Create a public hosted zone for the subdomain sock.blessedc.org
resource "aws_route53_zone" "sock-shop" {
  name = "sock.blessedc.org"
  comment = "Subdomain hosted zone for the Sock Shop project"
  tags = {
    Project     = "sock-shop"
    Environment = "prod"
  }
}

# Output the name servers and zone ID so we can delegate later
output "sock_zone_id" {
  value = aws_route53_zone.sock-shop.zone_id
}

output "sock_name_servers" {
  value = aws_route53_zone.sock-shop.name_servers
}
