# Capstone Project Journal
Project: Microservice Deployment on AWS EKS 
Author: [Your Name]  
Start Date: [SEP-29-2025]

---

## 📌 How to Use This Journal
- Log **daily or weekly updates** in bullet points.  
- Capture what you did, what you learned, and blockers.  
- This raw log will later be refined into your final documentation.

---

## 🗓 Project Log

### Week 1 (YYYY-MM-DD → YYYY-MM-DD)
**Focus:** Infrastructure setup with Terraform

- Day 1
  - Set up initial project structure
  - Initialized Terraform project with AWS provider.
  - Created `main.tf`, `variables.tf`, and `outputs.tf`.
  - Decided to use `t3.medium` instances for worker nodes.
  - Chose `desired_size=2`, `min_size=1`, `max_size=3` for project.
After running terraform apply  
  - run `aws eks list-clusters --region us-east-1` to confirm  
  - run `aws eks update-kubeconfig --name socks-shop-cluster --region us-east-1` to connect  
  - run `kubectl get nodes` to confirm and check the nodes
  - run `helm install socks-shop ./sock-shop --dry-run` to check if your setups are correct


## Deployment with Helms
 - run `helm version` to be sure you have helm installed
 - run `kubectl create namespace sock-shop` to create a namespace for better oganization
 - run `kubectl config set-context --current --namespace=sock-shop` to set as default namespace
 - run `helm create sock-shop` to create the helm project, delete the unnecessary files and configure values.yaml, deployment.yaml, service.yaml, ingress.yaml with the neccesary configurations
 - run `helm install socks-shop ./sock-shop --dry-run` to check if your setups are correct


