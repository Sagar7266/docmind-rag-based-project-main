#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
TF_DIR="$ROOT_DIR/infra/aws"
REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
REPOSITORY=$(terraform -chdir="$TF_DIR" output -raw backend_repository_url)
INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
FRONTEND_BUCKET=$(terraform -chdir="$TF_DIR" output -raw frontend_bucket)
DISTRIBUTION_ID=$(terraform -chdir="$TF_DIR" output -raw cloudfront_distribution_id)
APP_URL=$(terraform -chdir="$TF_DIR" output -raw app_url)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TAG=$(git -C "$ROOT_DIR" rev-parse --short HEAD)

wait_for_ssm_command() {
  local command_id="$1"
  local status

  for attempt in {1..180}; do
    status=$(aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$INSTANCE_ID" \
      --query Status \
      --output text)

    case "$status" in
      Success)
        return 0
        ;;
      Failed|Cancelled|TimedOut|DeliveryTimedOut|ExecutionTimedOut|Undeliverable|Terminated)
        aws ssm get-command-invocation \
          --region "$REGION" \
          --command-id "$command_id" \
          --instance-id "$INSTANCE_ID" \
          --query '{Status:Status,Details:StatusDetails,StdErr:StandardErrorContent,StdOut:StandardOutputContent}' \
          --output json >&2
        return 1
        ;;
    esac

    sleep 10
  done

  printf 'Timed out waiting for SSM command %s\n' "$command_id" >&2
  return 1
}

BOOTSTRAP_COMMANDS=$(python3 -c 'import json,sys; print(json.dumps({"commands": sys.argv[1:]}))' \
  "cloud-init status --wait --long" \
  "test -x /usr/bin/docker" \
  "test -x /usr/local/bin/docker-compose" \
  "test -f /opt/docmind/data/runtime.env")
BOOTSTRAP_COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "$BOOTSTRAP_COMMANDS" \
  --query 'Command.CommandId' \
  --output text)
wait_for_ssm_command "$BOOTSTRAP_COMMAND_ID"

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

docker buildx build \
  --platform linux/arm64 \
  --file "$ROOT_DIR/Dockerfile" \
  --tag "$REPOSITORY:$TAG" \
  --tag "$REPOSITORY:latest" \
  --push "$ROOT_DIR"

COMMANDS=$(python3 -c 'import json,sys; print(json.dumps({"commands": sys.argv[1:]}))' \
  "cd /opt/docmind" \
  "aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com" \
  "sed -i 's|^APP_CORS_ALLOWED_ORIGINS=.*|APP_CORS_ALLOWED_ORIGINS=$APP_URL|' /opt/docmind/data/runtime.env" \
  "docker-compose --env-file /opt/docmind/data/runtime.env -f /opt/docmind/compose.yaml pull api" \
  "docker-compose --env-file /opt/docmind/data/runtime.env -f /opt/docmind/compose.yaml up -d --force-recreate api")
COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "$COMMANDS" \
  --query 'Command.CommandId' \
  --output text)
wait_for_ssm_command "$COMMAND_ID"

npm --prefix "$ROOT_DIR/frontend/docmind-frontend" ci
npm --prefix "$ROOT_DIR/frontend/docmind-frontend" run build
aws s3 sync "$ROOT_DIR/frontend/docmind-frontend/dist" "s3://$FRONTEND_BUCKET" --delete --region "$REGION"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/*' >/dev/null

printf 'Deployment complete: %s\n' "$APP_URL"
