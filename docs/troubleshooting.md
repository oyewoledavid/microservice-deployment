# Troubleshooting Guide

## Known Issues and Solutions

### Issue 1: ACM Certificate Validation Timeout During Initial Deployment

**Problem Description:**
Running `terraform apply` on the complete infrastructure may cause ACM certificate validation to hang for 25+ minutes or timeout. This occurs because AWS ACM DNS validation requires proper DNS delegation to be in place before it can validate the certificate.

**Root Cause:**

- ACM creates DNS validation records in the Route53 hosted zone
- AWS attempts to query these records via public DNS to validate certificate ownership
- If the subdomain (`sock.blessedc.org`) is not properly delegated to the Route53 name servers in the parent domain, validation fails
- Terraform waits up to 45 minutes for validation before timing out

**Solution - Two-Phase Deployment:**

1. **Phase 1: Deploy Infrastructure Without SSL**

   ```bash
   # Comment out or rename the ACM certificate file
   mv terraform/acm-wildcard.tf terraform/acm-wildcard.tf.disabled

   # Deploy base infrastructure
   terraform apply --auto-approve
   ```

2. **Phase 2: Set Up DNS Delegation**

   ```bash
   # Get the name servers from terraform output
   terraform output sock_name_servers
   ```

   Add these NS records to your parent domain (`blessedc.org`) DNS settings:

3. **Phase 3: Verify DNS Delegation and Deploy SSL**

   ```bash
   # Verify delegation is working
   dig @8.8.8.8 NS sock.blessedc.org +short

   # Re-enable ACM certificate
   mv terraform/acm-wildcard.tf.disabled terraform/acm-wildcard.tf

   # Deploy SSL certificate
   terraform apply --auto-approve
   ```

**Prevention:**
Always ensure DNS delegation is configured before deploying ACM certificates, or use the two-phase deployment approach documented above.
