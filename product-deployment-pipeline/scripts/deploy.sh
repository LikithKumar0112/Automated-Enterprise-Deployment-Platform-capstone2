#!/bin/bash
# -E makes the ERR trap in main() also fire for failures inside functions.
set -eE

# Enterprise Deployment Script - manual/local equivalent of the Jenkinsfile.
# Usage: ./deploy.sh <environment: dev|stage|prod> <action: plan|apply|destroy> [image_tag] [run_tests] [security_scan]
# Run from the repo root.

ENVIRONMENT="${1:-dev}"
ACTION="${2:-apply}"
IMAGE_TAG="${3:-$(git rev-parse --short HEAD)}"
RUN_TESTS="${4:-true}"
SECURITY_SCAN="${5:-true}"

echo "🚀 Starting enterprise deployment"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Image Tag: $IMAGE_TAG"

VALID_ENVIRONMENTS=("dev" "stage" "prod")
if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${ENVIRONMENT} " ]]; then
    echo "❌ Invalid environment: $ENVIRONMENT (must be dev, stage, or prod)"
    exit 1
fi

# Non-secret, per-environment config. Kept inline (rather than a separate
# config/ directory) so this script is the single source of truth for
# what each environment name maps to.
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'UNKNOWN_ACCOUNT')"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
CLUSTER_NAME="analytics-${ENVIRONMENT}"
TF_STATE_BUCKET="analytics-tf-state-${AWS_ACCOUNT_ID}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/../.." && pwd)"
ROLLBACK_ARMED=false

if [[ "$ENVIRONMENT" != "dev" && "$SECURITY_SCAN" != "true" ]]; then
    echo "❌ security_scan cannot be disabled for $ENVIRONMENT"
    exit 1
fi

check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    required_commands=("docker" "terraform" "kubectl" "aws" "git" "jq" "mvn")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo "❌ Required command not found: $cmd"
            exit 1
        fi
    done
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon not running"
        exit 1
    fi
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured"
        exit 1
    fi
    echo "✅ All prerequisites satisfied"
}

# Source and IaC scans, before anything is built. Any finding stops the deploy.
run_source_scans() {
    if [[ "$SECURITY_SCAN" == "true" ]]; then
        echo "🔒 Running source and IaC scans..."
        docker run --rm -v "$(pwd):/src" returntocorp/semgrep semgrep scan --config auto --error
        docker run --rm -v "$(pwd)/product-infrastructure:/iac" bridgecrew/checkov:3.3.19 \
            -d /iac --framework terraform --compact --quiet --baseline /iac/.checkov.baseline
        echo "✅ Source and IaC scans passed"
    fi
}

# Runs after the build and before the push, so a failing image never reaches ECR.
run_image_scans() {
    if [[ "$SECURITY_SCAN" == "true" ]]; then
        for image in "analytics-api" "analytics-web" "analytics-data-processor"; do
            "$SCRIPTS_DIR/scan-image.sh" "$ECR_REGISTRY/$image:$IMAGE_TAG"
        done
        echo "✅ Image scans passed"
    fi
}

build_images() {
    echo "🏗️ Building Docker images (single multi-target Dockerfile in product-docker/)..."
    cd product-docker
    ./build-scripts/stage-local-app.sh
    docker build --target api           -t "$ECR_REGISTRY/analytics-api:$IMAGE_TAG"            -t "$ECR_REGISTRY/analytics-api:latest"            .
    docker build --target webapp        -t "$ECR_REGISTRY/analytics-web:$IMAGE_TAG"             -t "$ECR_REGISTRY/analytics-web:latest"            .
    docker build --target data-processor -t "$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG"  -t "$ECR_REGISTRY/analytics-data-processor:latest" .
    cd ..
}

push_images() {
    echo "📦 Pushing images to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    for image in "analytics-api" "analytics-web" "analytics-data-processor"; do
        docker push "$ECR_REGISTRY/$image:$IMAGE_TAG"
        docker push "$ECR_REGISTRY/$image:latest"
    done
    echo "✅ Images pushed"
}

run_tests() {
    if [[ "$RUN_TESTS" == "true" ]]; then
        echo "🧪 Running tests..."
        (cd app/api && mvn test)
        (cd app/data-processor && mvn test)
        echo "✅ Tests completed"
    fi
}

# Non-dev environments need a typed confirmation, and destroy always does.
confirm_action() {
    if [[ "$ACTION" == "destroy" || ( "$ACTION" == "apply" && "$ENVIRONMENT" != "dev" ) ]]; then
        read -r -p "Type '$ENVIRONMENT' to confirm $ACTION: " answer || answer=""
        if [[ "$answer" != "$ENVIRONMENT" ]]; then
            echo "Aborted: nothing was changed."
            exit 1
        fi
    fi
}

deploy_infrastructure() {
    echo "🛠️ Deploying infrastructure (workspace: $ENVIRONMENT)..."
    cd product-infrastructure

    terraform init \
        -backend-config="bucket=$TF_STATE_BUCKET" \
        -backend-config="region=$AWS_REGION"

    terraform workspace select "$ENVIRONMENT" 2>/dev/null || terraform workspace new "$ENVIRONMENT"

    case $ACTION in
        "plan")
            terraform plan -var-file="environments/$ENVIRONMENT/$ENVIRONMENT.tfvars" -var="image_tag=$IMAGE_TAG"
            ;;
        "apply")
            terraform apply -auto-approve -var-file="environments/$ENVIRONMENT/$ENVIRONMENT.tfvars" -var="image_tag=$IMAGE_TAG"
            ;;
        "destroy")
            terraform destroy -auto-approve -var-file="environments/$ENVIRONMENT/$ENVIRONMENT.tfvars"
            ;;
        *)
            echo "❌ Invalid action: $ACTION"
            exit 1
            ;;
    esac

    cd ..
    echo "✅ Infrastructure deployment completed"
}

deploy_kubernetes() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "☸️ Deploying to Kubernetes..."
        aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
        kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -

        "$SCRIPTS_DIR/sync-secrets.sh" "$ENVIRONMENT"

        cd product-kubernetes
        ROLLBACK_ARMED=true
        sed -e "s#analytics-api:latest#$ECR_REGISTRY/analytics-api:$IMAGE_TAG#g" \
            -e "s#analytics-web:latest#$ECR_REGISTRY/analytics-web:$IMAGE_TAG#g" \
            -e "s#analytics-data-processor:latest#$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG#g" \
            deployment.yaml > deployment.rendered.yaml

        kubectl apply -f configmap.yaml
        kubectl apply -f deployment.rendered.yaml
        kubectl apply -f service.yaml
        kubectl apply -f ingress.yaml

        # Waits for the new pods; `kubectl wait` can pass on the old ones.
        kubectl rollout status deployment/analytics-api -n analytics --timeout=300s
        kubectl rollout status deployment/analytics-web -n analytics --timeout=300s

        cd ..
        echo "✅ Kubernetes deployment completed"
    fi
}

run_smoke_tests() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "🚬 Running smoke tests..."
        API_ENDPOINT=$(kubectl get ingress analytics-api -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        WEB_ENDPOINT=$(kubectl get ingress analytics-web -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

        "$SCRIPTS_DIR/health-check.sh" "http://$API_ENDPOINT" /actuator/health 30 10 api.analytics.company.com
        "$SCRIPTS_DIR/health-check.sh" "http://$WEB_ENDPOINT" /health 30 10 app.analytics.company.com
        ROLLBACK_ARMED=false
        echo "✅ Smoke tests passed"
    fi
}

on_failure() {
    trap - ERR
    echo "❌ Failed, see the output above"
    local detail="Deployment failed for $ENVIRONMENT"
    if [[ "$ROLLBACK_ARMED" == "true" ]]; then
        if "$SCRIPTS_DIR/rollback.sh" "$ENVIRONMENT"; then
            detail+=" - rolled back to the previous version"
        else
            detail+=" - ROLLBACK FAILED, needs manual action"
        fi
    fi
    send_notification "FAILED" "$detail"
}

send_notification() {
    local status=$1
    local message=$2
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Deployment $status: $message\"}" "$SLACK_WEBHOOK_URL"
    fi
    mkdir -p "$REPO_ROOT/logs"
    echo "$(date): $status - $message" >> "$REPO_ROOT/logs/deployments.log"
}

main() {
    START_TIME=$(date +%s)
    trap on_failure ERR

    check_prerequisites
    confirm_action

    if [[ "$ACTION" == "apply" ]]; then
        run_source_scans
        run_tests
        build_images
        run_image_scans
        push_images
    fi

    deploy_infrastructure
    deploy_kubernetes
    run_smoke_tests

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    send_notification "SUCCESS" "$ACTION completed for $ENVIRONMENT in ${DURATION}s"
    echo "🎉 $ACTION completed successfully! (${DURATION}s)"
}

main
