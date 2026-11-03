# AWS public demo deployment

For the short end-to-end checklist, see [Overall AWS steps](OVERALL_STEPS.md).

This deployment publishes the React app at the CloudFront-provided HTTPS URL; no purchased or registered domain is required. A small ARM EC2 instance runs Spring Boot and pgvector PostgreSQL, Amazon Bedrock provides chat and embeddings, and private S3 plus CloudFront hosts the frontend. CloudFront connects to the API over HTTPS using a Let's Encrypt certificate for an EIP-derived `sslip.io` hostname. This depends on the external `sslip.io` DNS service for the API origin. The setup has no high availability; the default `t4g.small` has only 2 GiB RAM. Large uploads, concurrent requests, or memory pressure may require a larger instance and increase costs. Bedrock invocations and traffic add variable charges. AWS Budgets sends alerts but does not cap or stop charges.

Do not use this single-instance demo setup for sensitive production workloads. It uses Hibernate schema auto-update and a single database host; production services should use managed PostgreSQL, migrations, monitoring, and a high-availability design.

## Prerequisites

- An AWS account with billing alerts enabled and Amazon Bedrock model access enabled in the chosen region.
- AWS CLI v2, Terraform 1.6+, Docker with Buildx, Node.js/npm, Git, and Python 3 on the deployment machine.
- An email address for AWS budget notifications and a contact email for Let's Encrypt.

The default AWS region is `ap-south-1`; confirm the configured Nova Micro and Titan Text Embeddings V2 models are available there and request model access before deploying. Override the region/model IDs in `infra/aws/terraform.tfvars` if needed. Credentials are obtained from the local AWS CLI for provisioning and from an EC2 IAM role at runtime. Do not put AWS access keys, JWT secrets, or database passwords in Terraform variables or source control.

## Review cost before creating resources

Create `infra/aws/terraform.tfvars` locally (it is git-ignored):

```hcl
budget_email       = "you@example.com"
acme_email         = "you@example.com"
aws_region         = "ap-south-1"
instance_type      = "t4g.small"
monthly_budget_usd = 25
```

The baseline estimate depends on region and current AWS pricing. Check the EC2 instance, 20-GiB gp3 data volume, public IPv4, S3, and CloudFront costs in the [AWS Pricing Calculator](https://calculator.aws/) before applying. Bedrock model calls and traffic are additional. The budget notification is an alert, not a spending limit.

Initialize and inspect the plan; this does not create resources:

```bash
terraform -chdir=infra/aws init
terraform -chdir=infra/aws validate
terraform -chdir=infra/aws plan
```

Review the plan and estimated charges before creating resources:

```bash
terraform -chdir=infra/aws apply
```

## Deploy the application

The backend Docker image is built locally for ARM64 and pushed to the Terraform-created ECR repository. The frontend is built locally and uploaded to private S3. The deploy script uses SSM to update the EC2 app; no inbound SSH port is opened.

```bash
./infra/aws/deploy.sh
```

The script expects Terraform apply to have completed, the EC2 instance to be online in Systems Manager, and local AWS credentials with ECR push, S3 frontend upload, CloudFront invalidation, and SSM send-command permissions. It builds the frontend and backend, configures the API's exact allowed frontend origin, deploys both, and prints the CloudFront URL.

CloudFront routes `/api/*` to the EC2 origin over HTTPS, forwards auth/content headers without caching, and allows a 120-second origin read timeout for SSE. Caddy obtains and renews the origin certificate through Let's Encrypt. Port 443 on the instance accepts only CloudFront origin-facing traffic; port 80 is open for ACME HTTP validation and redirects to HTTPS. Allow time for the origin certificate and CloudFront distribution to become ready.

## Data, model migration, and recovery

Production uses Amazon Nova Micro for chat and Titan Text Embeddings V2 at 1024 dimensions by default. These embeddings are not interchangeable with existing Ollama/Qwen embeddings even though the dimensions match. This stack starts with a new pgvector database; users must upload their documents again. The original uploaded files are not retained by DocMind.

The encrypted, separately attached EBS volume stores PostgreSQL data and generated runtime secrets. A daily `pg_dump` is uploaded to an encrypted private S3 bucket and expires after 30 days. Verify backups and practice a restore before relying on them. The EBS volume has Terraform `prevent_destroy`; intentionally deleting it requires removing that safeguard only after taking a verified backup. Keep the local Terraform state file private and backed up; it is ignored by Git.

Bedrock model IDs and region are configurable. The EC2 role only grants invoke permissions for the two configured foundation model IDs. If a selected Bedrock model requires an inference profile or a different IAM resource ARN, adjust the policy before deploying that model. User registration is public in the current app, so new accounts can create Bedrock usage; monitor usage and close registration when the demo is not actively shared. Use AWS Budgets and review Bedrock usage regularly; the budget alerts do not enforce a hard limit.

For Ollama local development, see [Ollama setup](OLLAMA_SETUP.md).
