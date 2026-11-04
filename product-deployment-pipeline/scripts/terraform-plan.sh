#!/bin/bash
set -euo pipefail

cd product-infrastructure
terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=$AWS_REGION"
terraform workspace select "$ENVIRONMENT" || terraform workspace new "$ENVIRONMENT"

JENKINS_ROLE_ARN=$(aws sts get-caller-identity --query Arn --output text)
terraform plan \
    -var-file="environments/$ENVIRONMENT/$ENVIRONMENT.tfvars" \
    -var="image_tag=$IMAGE_TAG" \
    -var="jenkins_role_arn=$JENKINS_ROLE_ARN" \
    -out=tfplan.binary
terraform show -json tfplan.binary > tfplan.json
