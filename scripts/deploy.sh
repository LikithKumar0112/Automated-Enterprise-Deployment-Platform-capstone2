#!/bin/bash
set -e

# Enterprise Deployment Script
# Usage: ./deploy.sh <environment> <action> [options]

ENVIRONMENT="${1:-dev}"
ACTION="${2:-apply}"
IMAGE_TAG="${3:-$(git rev-parse --short HEAD)}"
RUN_TESTS="${4:-true}"
SECURITY_SCAN="${5:-true}"

echo "🚀 Starting enterprise deployment"
echo "Environment: $ENVIRONMENT"
echo "Action: $ACTION"
echo "Image Tag: $IMAGE_TAG"

# Validate environment
VALID_ENVIRONMENTS=("dev" "staging" "prod")
if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${ENVIRONMENT} " ]]; then
    echo "❌ Invalid environment: $ENVIRONMENT"
    exit 1
fi

# Load environment-specific configuration
source "config/$ENVIRONMENT.env"

# Function to check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    required_commands=("docker" "terraform" "kubectl" "aws" "git" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo "❌ Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        echo "❌ Docker daemon not running"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ AWS credentials not configured"
        exit 1
    fi
    
    echo "✅ All prerequisites satisfied"
}

# Function to run security scans
run_security_scans() {
    if [[ "$SECURITY_SCAN" == "true" ]]; then
        echo "🔒 Running security scans..."
        
        # SAST with Semgrep
        docker run --rm -v "$(pwd):/src" returntocorp/semgrep semgrep scan --config auto
        
        # Container vulnerability scanning
        for image in "analytics-api" "analytics-web"; do
            echo "Scanning $image..."
            docker run --rm \
                -v /var/run/docker.sock:/var/run/docker.sock \
                aquasec/trivy:latest \
                image --exit-code 1 --severity HIGH,CRITICAL \
                "$ECR_REGISTRY/$image:$IMAGE_TAG"
        done
        
        # Infrastructure scanning with checkov
        docker run --rm -v "$(pwd):/iac" bridgecrew/checkov -d /iac/terraform
        
        echo "✅ Security scans completed"
    fi
}

# Function to build and push images
build_and_push_images() {
    echo "🏗️ Building Docker images..."
    
    # Build API
    docker build \
        -t "$ECR_REGISTRY/analytics-api:$IMAGE_TAG" \
        -t "$ECR_REGISTRY/analytics-api:latest" \
        -f docker/api/Dockerfile .
    
    # Build Web
    docker build \
        -t "$ECR_REGISTRY/analytics-web:$IMAGE_TAG" \
        -t "$ECR_REGISTRY/analytics-web:latest" \
        -f docker/webapp/Dockerfile .
    
    echo "📦 Pushing images to ECR..."
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_REGISTRY"
    
    # Push images
    docker push "$ECR_REGISTRY/analytics-api:$IMAGE_TAG"
    docker push "$ECR_REGISTRY/analytics-api:latest"
    docker push "$ECR_REGISTRY/analytics-web:$IMAGE_TAG"
    docker push "$ECR_REGISTRY/analytics-web:latest"
    
    echo "✅ Images built and pushed"
}

# Function to run tests
run_tests() {
    if [[ "$RUN_TESTS" == "true" ]]; then
        echo "🧪 Running tests..."
        
        # Unit tests
        cd app
        mvn test
        cd ..
        
        # Integration tests
        docker-compose -f docker-compose.test.yml up --abort-on-container-exit
        docker-compose -f docker-compose.test.yml down
        
        echo "✅ Tests completed"
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    echo "🛠️ Deploying infrastructure..."
    
    cd "terraform/environments/$ENVIRONMENT"
    
    # Initialize Terraform
    terraform init \
        -backend-config="bucket=$TF_STATE_BUCKET" \
        -backend-config="key=$TF_STATE_KEY" \
        -backend-config="region=$AWS_REGION"
    
    case $ACTION in
        "plan")
            terraform plan \
                -var="environment=$ENVIRONMENT" \
                -var="image_tag=$IMAGE_TAG"
            ;;
        "apply")
            terraform apply \
                -auto-approve \
                -var="environment=$ENVIRONMENT" \
                -var="image_tag=$IMAGE_TAG"
            ;;
        "destroy")
            terraform destroy \
                -auto-approve \
                -var="environment=$ENVIRONMENT"
            ;;
        *)
            echo "❌ Invalid action: $ACTION"
            exit 1
            ;;
    esac
    
    # Get outputs
    terraform output -json > outputs.json
    CLUSTER_ENDPOINT=$(jq -r '.cluster_endpoint.value' outputs.json)
    
    cd ../..
    
    echo "✅ Infrastructure deployment completed"
}

# Function to deploy to Kubernetes
deploy_kubernetes() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "☸️ Deploying to Kubernetes..."
        
        # Update kubeconfig
        aws eks update-kubeconfig \
            --name "$CLUSTER_NAME" \
            --region "$AWS_REGION"
        
        # Create namespace if not exists
        kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -
        
        # Deploy with kustomize
        cd "kubernetes/overlays/$ENVIRONMENT"
        
        # Update images
        kustomize edit set image \
            analytics-api="$ECR_REGISTRY/analytics-api:$IMAGE_TAG" \
            analytics-web="$ECR_REGISTRY/analytics-web:$IMAGE_TAG"
        
        # Apply
        kustomize build . | kubectl apply -f -
        
        # Wait for deployment
        kubectl wait --for=condition=available \
            --timeout=300s \
            deployment/analytics-api -n analytics
        kubectl wait --for=condition=available \
            --timeout=300s \
            deployment/analytics-web -n analytics
        
        cd ../../..
        
        echo "✅ Kubernetes deployment completed"
    fi
}

# Function to run smoke tests
run_smoke_tests() {
    if [[ "$ACTION" == "apply" ]]; then
        echo "🚬 Running smoke tests..."
        
        # Get endpoints
        API_ENDPOINT=$(kubectl get ingress analytics-api -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        WEB_ENDPOINT=$(kubectl get ingress analytics-web -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        # Test API
        if [[ -n "$API_ENDPOINT" ]]; then
            echo "Testing API endpoint: $API_ENDPOINT"
            for i in {1..30}; do
                if curl -f "https://$API_ENDPOINT/actuator/health" &> /dev/null; then
                    echo "✅ API health check passed"
                    break
                fi
                sleep 5
            done
        fi
        
        # Test Web
        if [[ -n "$WEB_ENDPOINT" ]]; then
            echo "Testing Web endpoint: $WEB_ENDPOINT"
            for i in {1..30}; do
                if curl -f "https://$WEB_ENDPOINT/health" &> /dev/null; then
                    echo "✅ Web health check passed"
                    break
                fi
                sleep 5
            done
        fi
        
        echo "✅ Smoke tests completed"
    fi
}

# Function to send notifications
send_notification() {
    local status=$1
    local message=$2
    
    # Send to Slack
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Deployment $status: $message\"}" \
            "$SLACK_WEBHOOK_URL"
    fi
    
    # Log to file
    echo "$(date): $status - $message" >> "logs/deployments.log"
}

# Main execution
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
    
    echo "🎉 Deployment completed successfully!"
    echo "⏱️  Total duration: ${DURATION}s"
}

# Execute main function
main
