#!/bin/bash
set -e

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
ECR_REGISTRY="123456789012.dkr.ecr.us-east-1.amazonaws.com"
CLUSTER_NAME="analytics-${ENVIRONMENT}"
TF_STATE_BUCKET="analytics-tf-state-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'UNKNOWN_ACCOUNT')"

check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    required_commands=("docker" "terraform" "kubectl" "aws" "git" "jq")
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

run_security_scans() {
    if [[ "$SECURITY_SCAN" == "true" ]]; then
        echo "🔒 Running security scans..."
        docker run --rm -v "$(pwd):/src" returntocorp/semgrep semgrep scan --config auto
        for image in "analytics-api" "analytics-web" "analytics-data-processor"; do
            echo "Scanning $image..."
            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                aquasec/trivy:latest image --exit-code 1 --severity HIGH,CRITICAL \
                "$ECR_REGISTRY/$image:$IMAGE_TAG"
        done
        docker run --rm -v "$(pwd)/product-infrastructure:/iac" bridgecrew/checkov -d /iac
        echo "✅ Security scans completed"
    fi
}

build_and_push_images() {
    echo "🏗️ Building Docker images (single multi-target Dockerfile in product-docker/)..."
    cd product-docker
    docker build --target api           -t "$ECR_REGISTRY/analytics-api:$IMAGE_TAG"            -t "$ECR_REGISTRY/analytics-api:latest"            .
    docker build --target webapp        -t "$ECR_REGISTRY/analytics-web:$IMAGE_TAG"             -t "$ECR_REGISTRY/analytics-web:latest"            .
    docker build --target data-processor -t "$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG"  -t "$ECR_REGISTRY/analytics-data-processor:latest" .
    cd ..

    echo "📦 Pushing images to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    for image in "analytics-api" "analytics-web" "analytics-data-processor"; do
        docker push "$ECR_REGISTRY/$image:$IMAGE_TAG"
        docker push "$ECR_REGISTRY/$image:latest"
    done
    echo "✅ Images built and pushed"
}

run_tests() {
    if [[ "$RUN_TESTS" == "true" ]]; then
        echo "🧪 Running tests..."
        cd app && mvn test && cd ..
        echo "✅ Tests completed"
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

    terraform output -json > outputs.json
    CLUSTER_ENDPOINT=$(jq -r '.cluster_endpoint.value' outputs.json)
    cd ..
    echo "✅ Infrastructure deployment completed"
}

deploy_kubernetes() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "☸️ Deploying to Kubernetes..."
        aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
        kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -

        cd product-kubernetes
        cp deployment.yaml deployment.yaml.bak
        sed -i "s#analytics-api:latest#$ECR_REGISTRY/analytics-api:$IMAGE_TAG#g" deployment.yaml
        sed -i "s#analytics-web:latest#$ECR_REGISTRY/analytics-web:$IMAGE_TAG#g" deployment.yaml
        sed -i "s#analytics-data-processor:latest#$ECR_REGISTRY/analytics-data-processor:$IMAGE_TAG#g" deployment.yaml

        kubectl apply -f configmap.yaml
        kubectl apply -f secrets.yaml
        kubectl apply -f deployment.yaml
        kubectl apply -f service.yaml
        kubectl apply -f ingress.yaml

        kubectl wait --for=condition=available --timeout=300s deployment/analytics-api -n analytics
        kubectl wait --for=condition=available --timeout=300s deployment/analytics-web -n analytics

        mv deployment.yaml.bak deployment.yaml
        cd ..
        echo "✅ Kubernetes deployment completed"
    fi
}

run_smoke_tests() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "🚬 Running smoke tests..."
        API_ENDPOINT=$(kubectl get ingress analytics-api -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        WEB_ENDPOINT=$(kubectl get ingress analytics-web -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

        if [[ -n "$API_ENDPOINT" ]]; then
            for i in {1..30}; do
                curl -f "https://$API_ENDPOINT/actuator/health" &> /dev/null && { echo "✅ API health check passed"; break; }
                sleep 5
            done
        fi
        if [[ -n "$WEB_ENDPOINT" ]]; then
            for i in {1..30}; do
                curl -f "https://$WEB_ENDPOINT/health" &> /dev/null && { echo "✅ Web health check passed"; break; }
                sleep 5
            done
        fi
        echo "✅ Smoke tests completed"
    fi
}

send_notification() {
    local status=$1
    local message=$2
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Deployment $status: $message\"}" "$SLACK_WEBHOOK_URL"
    fi
    mkdir -p logs
    echo "$(date): $status - $message" >> "logs/deployments.log"
}

main() {
    START_TIME=$(date +%s)
    trap 'send_notification "FAILED" "Deployment failed for $ENVIRONMENT"' ERR

    check_prerequisites

    if [[ "$ACTION" == "apply" ]]; then
        run_security_scans
        run_tests
        build_and_push_images
    fi

    deploy_infrastructure
    deploy_kubernetes
    run_smoke_tests

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    send_notification "SUCCESS" "Deployment completed for $ENVIRONMENT in ${DURATION}s"
    echo "🎉 Deployment completed successfully! (${DURATION}s)"
}

main
