#!/bin/bash
set -euo pipefail

REGION="us-east-1"
FORCE=false

# Parse args
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
  echo "⚠️ Force mode enabled: ENIs will be detached before deletion!"
fi

echo "🧹 Starting cleanup for Socks Shop EKS in $REGION"

# -------------------------
# Detect all VPC IDs from Terraform state or AWS
# -------------------------
echo "📌 Detecting VPC IDs..."
VPC_IDS=$(terraform state list 2>/dev/null | grep aws_vpc || true)

if [ -n "$VPC_IDS" ]; then
  echo "🔎 Found VPCs in Terraform state:"
  VPC_LIST=()
  for V in $VPC_IDS; do
    ID=$(terraform state show $V 2>/dev/null | grep 'id =' | awk '{print $3}' || true)
    if [ -n "$ID" ]; then
      VPC_LIST+=("$ID")
    fi
  done
else
  echo "⚠️ No VPCs found in Terraform state. Falling back to AWS CLI..."
  VPC_LIST=($(aws ec2 describe-vpcs --region $REGION \
    --query 'Vpcs[?IsDefault==`false`].VpcId' --output text || true))
fi

if [ ${#VPC_LIST[@]} -eq 0 ]; then
  echo "❌ No VPCs detected. Exiting."
  exit 0
fi

echo "✅ Targeting VPCs: ${VPC_LIST[@]}"

# -------------------------
# Loop through each VPC
# -------------------------
for VPC_ID in "${VPC_LIST[@]}"; do
  echo "=============================="
  echo "🧹 Cleaning VPC: $VPC_ID"
  echo "=============================="

  # Phase 1: Destroy EKS
  echo "📌 Phase 1: Destroying EKS node groups and cluster..."
  terraform destroy -target=aws_eks_node_group.socks_shop_nodes -auto-approve || echo "ℹ️ Node groups already gone."
  terraform destroy -target=aws_eks_cluster.socks-shop-cluster -auto-approve || echo "ℹ️ Cluster already gone."

  # Phase 2: Delete Load Balancers
  echo "📌 Phase 2: Deleting AWS Load Balancers in VPC $VPC_ID..."
  LBS=$(aws elbv2 describe-load-balancers --region $REGION \
    --query 'LoadBalancers[*].{ARN:LoadBalancerArn,VPC:VpcId}' \
    --output json | jq -r ".[] | select(.VPC==\"$VPC_ID\") | .ARN")

  if [ -z "$LBS" ]; then
    echo "ℹ️ No load balancers found in VPC $VPC_ID"
  else
    for LB in $LBS; do
      echo "🗑️ Deleting Load Balancer: $LB"
      LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $LB --region $REGION --query 'Listeners[*].ListenerArn' --output text || true)
      for L in $LISTENERS; do
        echo "   🔌 Deleting Listener: $L"
        aws elbv2 delete-listener --listener-arn $L --region $REGION || true
      done
      aws elbv2 delete-load-balancer --load-balancer-arn $LB --region $REGION || true
    done
  fi

  # Delete target groups
  TGS=$(aws elbv2 describe-target-groups --region $REGION --query 'TargetGroups[*].{ARN:TargetGroupArn,VPC:VpcId}' --output json | jq -r ".[] | select(.VPC==\"$VPC_ID\") | .ARN")
  if [ -z "$TGS" ]; then
    echo "ℹ️ No target groups found in VPC $VPC_ID"
  else
    for TG in $TGS; do
      echo "🗑️ Deleting Target Group: $TG"
      aws elbv2 delete-target-group --target-group-arn $TG --region $REGION || true
    done
  fi

  # Phase 3: Delete NAT Gateways & Elastic IPs
  echo "📌 Phase 3: Deleting NAT Gateways and Elastic IPs in VPC $VPC_ID..."
  NATS=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text || true)
  if [ -z "$NATS" ]; then
    echo "ℹ️ No NAT gateways found in VPC $VPC_ID"
  else
    for NAT in $NATS; do
      echo "🗑️ Deleting NAT Gateway: $NAT"
      aws ec2 delete-nat-gateway --nat-gateway-id $NAT --region $REGION || true
    done
  fi

  EIPS=$(aws ec2 describe-addresses --region $REGION --query 'Addresses[*].AllocationId' --output text || true)
  if [ -z "$EIPS" ]; then
    echo "ℹ️ No Elastic IPs found"
  else
    for EIP in $EIPS; do
      echo "🗑️ Releasing Elastic IP: $EIP"
      aws ec2 release-address --allocation-id $EIP --region $REGION || true
    done
  fi

  # Phase 4: Delete ENIs
  echo "📌 Phase 4: Deleting ENIs in VPC $VPC_ID..."
  ENIS=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,Attachment:Attachment.AttachmentId}' --output json)

  if [ "$(echo "$ENIS" | jq length)" -eq 0 ]; then
    echo "ℹ️ No ENIs found in VPC $VPC_ID"
  else
    for ROW in $(echo "$ENIS" | jq -c '.[]'); do
      ENI=$(echo "$ROW" | jq -r '.ID')
      STATUS=$(echo "$ROW" | jq -r '.Status')
      ATTACHMENT=$(echo "$ROW" | jq -r '.Attachment')

      if [ "$STATUS" == "available" ]; then
        echo "🗑️ Deleting detached ENI: $ENI"
        aws ec2 delete-network-interface --network-interface-id $ENI --region $REGION || true
      elif [ "$FORCE" == true ] && [ "$ATTACHMENT" != "null" ]; then
        echo "⚠️ Force detaching ENI: $ENI (Attachment: $ATTACHMENT)"
        aws ec2 detach-network-interface --attachment-id $ATTACHMENT --region $REGION || true
        echo "🗑️ Deleting ENI: $ENI"
        aws ec2 delete-network-interface --network-interface-id $ENI --region $REGION || true
      else
        echo "⏭️ Skipping in-use ENI: $ENI (status: $STATUS)"
      fi
    done
  fi

  # Phase 5: Destroy IGW, Subnets, VPC
  echo "📌 Phase 5: Destroying IGW, Subnets, and VPC $VPC_ID with Terraform..."
  terraform destroy -target=aws_internet_gateway.this -auto-approve || echo "ℹ️ IGW already gone."
  terraform destroy -target=aws_subnet.this -auto-approve || echo "ℹ️ Subnets already gone."
  terraform destroy -target=aws_vpc.this -auto-approve || echo "ℹ️ VPC already gone."

done

# Phase 6: Final full destroy
echo "📌 Phase 6: Final full destroy for everything..."
terraform destroy -auto-approve || echo "ℹ️ Nothing left to destroy."

echo "✅ Cleanup complete for all VPCs: ${VPC_LIST[@]}"
