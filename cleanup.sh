#!/bin/bash

# Automated AWS Infrastructure Cleanup Script
# This script handles complete cleanup of Terraform-managed infrastructure
# including Kubernetes-managed resources that prevent normal destruction

set -e  # Exit on any error

# Configuration
REGION="us-east-1"
TERRAFORM_DIR="./terraform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_cli() {
    log_info "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity --region $REGION &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    log_success "AWS CLI is properly configured"
}

# Function to check if Terraform is available
check_terraform() {
    log_info "Checking Terraform installation..."
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed or not in PATH"
        exit 1
    fi
    log_success "Terraform is available: $(terraform version | head -1)"
}

# Function to get VPC ID from Terraform state
get_vpc_id() {
    local vpc_id=""
    
    # Try to get VPC ID from Terraform state first
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        vpc_id=$(terraform -chdir="$TERRAFORM_DIR" show -json 2>/dev/null | jq -r '.values.root_module.child_modules[]?.resources[]? | select(.type=="aws_vpc") | .values.id' 2>/dev/null | head -1)
    fi
    
    # If not found in state, try to find VPC by tag
    if [ -z "$vpc_id" ] || [ "$vpc_id" = "null" ]; then
        vpc_id=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=eks-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    fi
    
    if [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ] && [ -n "$vpc_id" ]; then
        echo "$vpc_id"
    fi
}

# Function to clean up load balancers
cleanup_load_balancers() {
    local vpc_id="$1"
    
    log_info "Checking for load balancers in VPC: $vpc_id"
    
    # Get all load balancers in the VPC
    local lb_arns=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" --output text 2>/dev/null)
    
    if [ -n "$lb_arns" ] && [ "$lb_arns" != "None" ]; then
        for lb_arn in $lb_arns; do
            log_info "Deleting load balancer: $lb_arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region $REGION
            log_success "Load balancer deleted: $lb_arn"
        done
        
        # Wait for load balancers to be fully deleted
        log_info "Waiting for load balancers to be fully removed..."
        sleep 30
    else
        log_info "No load balancers found in VPC"
    fi
}

# Function to clean up network interfaces
cleanup_network_interfaces() {
    local vpc_id="$1"
    
    log_info "Checking for network interfaces in VPC: $vpc_id"
    
    # Get subnets in the VPC
    local subnet_ids=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text 2>/dev/null)
    
    if [ -n "$subnet_ids" ] && [ "$subnet_ids" != "None" ]; then
        # Check for ENIs in these subnets
        local eni_ids=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=subnet-id,Values=$(echo $subnet_ids | tr ' ' ',')" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null)
        
        if [ -n "$eni_ids" ] && [ "$eni_ids" != "None" ]; then
            log_warning "Found network interfaces, waiting for AWS to clean them up..."
            local max_wait=300  # 5 minutes
            local wait_time=0
            
            while [ $wait_time -lt $max_wait ]; do
                local remaining_enis=$(aws ec2 describe-network-interfaces --region $REGION --filters "Name=subnet-id,Values=$(echo $subnet_ids | tr ' ' ',')" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null)
                
                if [ -z "$remaining_enis" ] || [ "$remaining_enis" = "None" ]; then
                    log_success "All network interfaces have been cleaned up"
                    break
                fi
                
                log_info "Waiting for network interfaces to be removed... ($wait_time/$max_wait seconds)"
                sleep 10
                wait_time=$((wait_time + 10))
            done
            
            if [ $wait_time -ge $max_wait ]; then
                log_warning "Network interfaces are taking longer than expected to clean up"
            fi
        else
            log_info "No network interfaces found in subnets"
        fi
    fi
}

# Function to clean up security groups
cleanup_security_groups() {
    local vpc_id="$1"
    
    log_info "Checking for security groups in VPC: $vpc_id"
    
    # Get all security groups except default
    local sg_ids=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null)
    
    if [ -n "$sg_ids" ] && [ "$sg_ids" != "None" ]; then
        for sg_id in $sg_ids; do
            log_info "Deleting security group: $sg_id"
            if aws ec2 delete-security-group --group-id "$sg_id" --region $REGION 2>/dev/null; then
                log_success "Security group deleted: $sg_id"
            else
                log_warning "Failed to delete security group: $sg_id (may have dependencies)"
            fi
        done
    else
        log_info "No custom security groups found in VPC"
    fi
}

# Function to run terraform destroy
terraform_destroy() {
    log_info "Running Terraform destroy..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize terraform if needed
    if [ ! -d ".terraform" ]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    # Run destroy with lock disabled to avoid state lock issues
    if terraform destroy -auto-approve -lock=false; then
        log_success "Terraform destroy completed successfully"
    else
        log_error "Terraform destroy failed"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# Function to clean up terraform state files
cleanup_terraform_state() {
    log_info "Cleaning up Terraform state files..."
    
    cd "$TERRAFORM_DIR"
    
    # Remove state files
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.tfstate.lock.info
    
    # Optionally remove .terraform directory (uncomment if desired)
    # rm -rf .terraform
    
    log_success "Terraform state files cleaned up"
    
    cd "$SCRIPT_DIR"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check for remaining VPCs
    local remaining_vpcs=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=eks-vpc" --query 'Vpcs[].VpcId' --output text 2>/dev/null)
    
    if [ -z "$remaining_vpcs" ] || [ "$remaining_vpcs" = "None" ]; then
        log_success "No VPCs found with tag Name=eks-vpc"
    else
        log_warning "Found remaining VPCs: $remaining_vpcs"
    fi
    
    # Check for load balancers
    local remaining_lbs=$(aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null)
    
    if [ -z "$remaining_lbs" ] || [ "$remaining_lbs" = "None" ]; then
        log_success "No load balancers found"
    else
        log_warning "Found remaining load balancers"
    fi
    
    log_success "Cleanup verification completed"
}

# Main execution
main() {
    echo "=========================================="
    echo "AWS Infrastructure Cleanup Script"
    echo "=========================================="
    
    # Pre-flight checks
    check_aws_cli
    check_terraform
    
    # Get VPC ID
    local vpc_id=$(get_vpc_id)
    
    if [ -n "$vpc_id" ]; then
        log_info "Found VPC to clean up: $vpc_id"
        
        # Clean up Kubernetes-managed resources
        cleanup_load_balancers "$vpc_id"
        cleanup_network_interfaces "$vpc_id"
        cleanup_security_groups "$vpc_id"
        
        # Run terraform destroy
        terraform_destroy
    else
        log_info "No VPC found, attempting Terraform destroy anyway..."
        terraform_destroy
    fi
    
    # Clean up state files
    cleanup_terraform_state
    
    # Verify cleanup
    verify_cleanup
    
    echo "=========================================="
    log_success "Cleanup completed successfully!"
    echo "=========================================="
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Automated AWS infrastructure cleanup script"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -r, --region   AWS region (default: us-east-1)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Run cleanup with default settings"
    echo "  $0 -r us-west-2      # Run cleanup in us-west-2 region"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main