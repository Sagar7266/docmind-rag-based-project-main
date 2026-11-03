# DocMind: Overall AWS Steps

The app is currently published at **<https://dafigvv92rhwn.cloudfront.net>**.

## Use the app

1. Open the link above.
2. Register an account or sign in.
3. Upload your documents, then ask questions in chat.

## Deploy or update the app

### One-time AWS setup

1. Install AWS CLI v2, Terraform 1.6+, Docker with Buildx, Node.js/npm, Git, and Python 3.
2. Configure AWS CLI credentials and confirm that the account has permission to create the resources in `infra/aws/main.tf`.
3. In Amazon Bedrock, request access to the configured Nova Micro chat model and Titan Text Embeddings V2 model in the configured AWS region.
4. Create `infra/aws/terraform.tfvars`:

   ```hcl
   budget_email       = "you@example.com"
   acme_email         = "you@example.com"
   aws_region         = "ap-south-1"
   instance_type      = "t4g.small"
   monthly_budget_usd = 25
   ```

5. Estimate the EC2, EBS, public IPv4, S3, CloudFront, and Bedrock costs with the [AWS Pricing Calculator](https://calculator.aws/). The AWS Budget sends alerts only; it does not limit spending.
6. Initialize and validate Terraform, then review the plan:

   ```bash
   terraform -chdir=infra/aws init
   terraform -chdir=infra/aws validate
   terraform -chdir=infra/aws plan
   ```

7. After reviewing the planned resources and estimated costs, create the infrastructure:

   ```bash
   terraform -chdir=infra/aws apply
   ```

8. Deploy the application:

   ```bash
   ./infra/aws/deploy.sh
   ```

   This builds and uploads the backend image, updates the EC2 app through Systems Manager, builds the frontend, uploads it to S3, and invalidates CloudFront.

### Future application updates

From the same local checkout that holds the Terraform state, update the code and run:

```bash
./infra/aws/deploy.sh
```

If you change infrastructure, first review `terraform -chdir=infra/aws plan`, then apply the reviewed changes before deploying. Keep the local Terraform state and its backup private; without that state, Terraform cannot safely manage the existing AWS resources.

## Verify the deployment

After deployment, the script prints the app URL. Check that the frontend loads and the API is reachable:

```bash
APP_URL=$(terraform -chdir=infra/aws output -raw app_url)
curl -I "$APP_URL/"
curl -i "$APP_URL/api/v1/documents/user"
```

The frontend should return `200`. The protected API should return `401` when called without a login token; that is expected.

## Important notes

- AWS charges continue while resources are running. Bedrock usage and internet traffic can add variable costs. Review AWS Billing and Cost Explorer regularly.
- The default EC2 instance is a small demo configuration, not highly available or suitable for sensitive production workloads.
- The API origin uses an EIP-derived `sslip.io` hostname and a Let's Encrypt certificate; origin TLS depends on that external DNS service.
- The database is on an encrypted EBS volume with `prevent_destroy`; do not remove or recreate it without a verified backup.
- This AWS deployment starts with a new database. Re-upload documents from any previous local setup.
- Public registration allows new accounts to generate Bedrock usage.

See [AWS deployment details](AWS_DEPLOYMENT.md) for architecture, permissions, model configuration, and recovery information.
