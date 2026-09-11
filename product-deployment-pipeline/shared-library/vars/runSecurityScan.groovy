// Shared step: container + IaC scanning with a single severity gate.
// Usage: runSecurityScan(image: "${ECR_REGISTRY}/analytics-api:${IMAGE_TAG}")
def call(Map config) {
    def severity = config.severity ?: 'HIGH,CRITICAL'

    sh """
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        aquasec/trivy:latest image --exit-code 1 --severity ${severity} ${config.image}
    """

    if (config.scanTerraform) {
        sh 'docker run --rm -v "$(pwd)/infra/product-infrastructure:/iac" bridgecrew/checkov -d /iac'
    }
}
