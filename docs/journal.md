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
- run `helm list -n kube-system` to check if AWS Load BAlancer is deployed and run `kubectl get pods -n kube-system | grep aws-load-balancer-controller` to see the load balancer running

- run `dig NS sock.blessedc.org +short` to confirm if dns propagation is working

sock_name_servers = tolist([
"ns-1168.awsdns-18.org",
"ns-1632.awsdns-12.co.uk",
"ns-349.awsdns-43.com",
"ns-670.awsdns-19.net",
])

sock_zone_id = "Z01734391FSQGPMUC39CQ"

## use helm to install external DNS

```yaml
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm install external-dns external-dns/external-dns \
--namespace external-dns \
--create-namespace \
--set provider=aws \
--set registry=txt \
--set txtOwnerId=sockshop \
--set domainFilters={sock.blessedc.org} \
--set aws.zoneType=public \
--set serviceAccount.create=true \
--set serviceAccount.name=external-dns \
--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::<IAM-ID>:role/eks-externaldns-role
```

- run `kubectl logs -n external-dns deploy/external-dns` to verify log out put of external dns
- run

```aws route53 list-resource-record-sets \
  --hosted-zone-id <YOUR_ZONE_ID> \
  --query "ResourceRecordSets[?Name == 'sock.blessedc.org.']"
```

To verify that external dns created record in route53

At this point your app should be available on http.

### Let’s Encrypt (cert-manager) setup for Https
acm_certificate_arn = "arn:aws:acm:us-east-1:354767057562:certificate/c52b74bb-b59c-40a0-ad51-3b2532c3d191""

## Updating Helm release with SSL certificate

Fixed duplicate output issue in terraform files, then updated the Helm release:

```bash
helm upgrade --install socks-shop ./sock-shop \
  --namespace sock-shop \
  --set ingress.certificateArn=$(cd terraform && terraform output -raw acm_certificate_arn)
```

**Note**: The `--install` flag ensures the command works whether the release exists or not.
**Issue Fixed**: Removed duplicate `acm_certificate_arn` output from outputs.tf (it was already defined in acm-cert.tf).

helm upgrade --install socks-shop ./sock-shop --namespace sock-shop --set ingress.certificateArn=$(cd terraform && terraform output -raw acm_certificate_arn)

## Verification

Check if the ingress has the certificate annotation
`kubectl get ingress -n sock-shop -o yaml`

Check the application URL
`kubectl get ingress -n sock-shop`

Test HTTPS access (once DNS propagates)
`curl -I https://sock.blessedc.org`

```bash
aws elbv2 describe-listeners \
  --load-balancer-arn <YOUR_ALB_ARN> \
  --region us-east-1 \
  --query 'Listeners[*].{Port:Port,Protocol:Protocol,Certificates:Certificates}'
```

## Monitoring
- Create a wildcard cert for `.sock.blessedc.org` this will also cover sock.blessedc.org will we use this cert for grafana.sock.blessedc.org and prometheus.blessedc.org later and any other we want.
### Deploy grafana and prometheus using helm
- create monitoring namespace run `kubectl create namespace monitoring`
- Add and Update 
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```
- Create monitoring value file
- install the monitoring stack 
```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring-values.yaml
```
- create grafana and prometheus ingress file
- Apply The ingress files
```bash
kubectl apply -f grafana-ingress.yaml
kubectl apply -f prometheus-ingress.yaml
```
- run `kubectl get ingress -n monitoring` to confirm the ingress
- run `kubectl logs -n external-dns deploy/external-dns | grep grafana.sock.blessedc.org -A3` to check external DNS has created record
Grafana and prometheus will not be available via HTTPS on grafana.sock.blessedc.org and prometheus.sock.blessedc.org respectively