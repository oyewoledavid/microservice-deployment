# IAM policy allowing ExternalDNS to manage Route53 records
data "aws_iam_policy_document" "externaldns" {
  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListHostedZones",
      "route53:ChangeResourceRecordSets"
    ]

    resources = ["arn:aws:route53:::hostedzone/${aws_route53_zone.sock-shop.zone_id}"]
  }

    statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListTagsForResource"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "externaldns" {
  name        = "ExternalDNSRoute53Policy"
  description = "Allow ExternalDNS to manage Route53 records"
  policy      = data.aws_iam_policy_document.externaldns.json
}

# Create IAM role for service account (IRSA) – using existing OIDC provider from EKS module
resource "aws_iam_role" "externaldns" {
  name = "eks-externaldns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = module.eks.oidc_provider_arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          "StringEquals" = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-dns:external-dns"
          }
        }
      }
    ]
  })

  depends_on = [
    module.eks
  ]
}

resource "aws_iam_role_policy_attachment" "externaldns_attach" {
  role       = aws_iam_role.externaldns.name
  policy_arn = aws_iam_policy.externaldns.arn
}



