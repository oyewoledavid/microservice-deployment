#!/bin/bash

# Automated AWS Infrastructure Deployment Script
# This script deploys the complete sock-shop infrastructure

set -e  # Exit on any error

# Configuration
REGION="us-east-1"
TERRAFORM_DIR="./terraform"
HELM_CHART_DIR="./sock-shop"
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! aws sts get-caller-identity --region $REGION &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed or not in PATH"
        exit 1
    fi
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

# Function to deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize terraform
    terraform init
    
    # Plan the deployment
    log_info "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    # Apply the plan
    log_info "Applying Terraform plan..."
    terraform apply tfplan
    
    # Get cluster name
    local cluster_name=$(terraform output -raw cluster_name)
    log_success "Infrastructure deployed successfully. Cluster: $cluster_name"
    
    cd "$SCRIPT_DIR"
    echo "$cluster_name"
}

# Function to configure kubectl
configure_kubectl() {
    local cluster_name="$1"
    
    log_info "Configuring kubectl for cluster: $cluster_name"
    
    # Update kubeconfig
    aws eks update-kubeconfig --region $REGION --name "$cluster_name"
    
    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if kubectl get nodes &>/dev/null; then
            log_success "Cluster is ready"
            break
        fi
        
        log_info "Waiting for cluster... ($wait_time/$max_wait seconds)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        log_error "Cluster did not become ready within timeout"
        exit 1
    fi
    
    # Show cluster info
    kubectl get nodes
}

# Function to install AWS Load Balancer Controller
install_alb_controller() {
    local cluster_name="$1"
    
    log_info "Installing AWS Load Balancer Controller..."
    
    # Create IAM service account
    eksctl create iamserviceaccount \
        --cluster="$cluster_name" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name AmazonEKSLoadBalancerControllerRole \
        --attach-policy-arn=arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
        --approve \
        --region="$REGION" 2>/dev/null || log_warning "IAM service account may already exist"
    
    # Add EKS Helm repository
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Install AWS Load Balancer Controller
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$cluster_name" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --wait
    
    log_success "AWS Load Balancer Controller installed"
}

# Function to deploy sock-shop application
deploy_sock_shop() {
    log_info "Deploying sock-shop application..."
    
    # Validate Helm chart
    helm lint "$HELM_CHART_DIR"
    
    # Install the Helm chart
    helm upgrade --install sock-shop "$HELM_CHART_DIR" \
        --create-namespace \
        --namespace default \
        --wait \
        --timeout=10m
    
    log_success "Sock-shop application deployed"
}

# Function to get application URL
get_application_url() {
    log_info "Getting application URL..."
    
    # Wait for ingress to get an address
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local ingress_url=$(kubectl get ingress sock-shop-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        
        if [ -n "$ingress_url" ]; then
            log_success "Application is available at: http://$ingress_url"
            return 0
        fi
        
        log_info "Waiting for ingress URL... ($wait_time/$max_wait seconds)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    log_warning "Ingress URL not available yet. Check later with: kubectl get ingress"
}

# Function to show deployment status
show_status() {
    log_info "Deployment status:"
    
    echo ""
    echo "Pods:"
    kubectl get pods
    
    echo ""
    echo "Services:"
    kubectl get services
    
    echo ""
    echo "Ingress:"
    kubectl get ingress
}

# Main execution
main() {
    echo "=========================================="
    echo "AWS Infrastructure Deployment Script"
    echo "=========================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    local cluster_name=$(deploy_infrastructure)
    
    # Configure kubectl
    configure_kubectl "$cluster_name"
    
    # Install AWS Load Balancer Controller
    install_alb_controller "$cluster_name"
    
    # Deploy application
    deploy_sock_shop
    
    # Get application URL
    get_application_url
    
    # Show status
    show_status
    
    echo "=========================================="
    log_success "Deployment completed successfully!"
    echo "=========================================="
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Automated AWS infrastructure deployment script"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help     Show this help message"
    echo "  -r, --region   AWS region (default: us-east-1)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                    # Deploy with default settings"
    echo "  $0 -r us-west-2      # Deploy in us-west-2 region"
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