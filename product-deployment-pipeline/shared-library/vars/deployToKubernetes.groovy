// Shared step: sed-substitute image tags into the flat product-kubernetes/
// manifests, apply them, and wait for rollout.
// Usage: deployToKubernetes(environment: 'stage', apiImage: '...', webImage: '...', dataProcessorImage: '...')
def call(Map config) {
    def namespace = config.namespace ?: 'analytics'

    dir('infra/product-kubernetes') {
        sh """
        kubectl create namespace ${namespace} --dry-run=client -o yaml | kubectl apply -f -

        sed -i "s#analytics-api:latest#${config.apiImage}#g" deployment.yaml
        sed -i "s#analytics-web:latest#${config.webImage}#g" deployment.yaml
        sed -i "s#analytics-data-processor:latest#${config.dataProcessorImage}#g" deployment.yaml

        kubectl apply -f configmap.yaml
        kubectl apply -f secrets.yaml
        kubectl apply -f deployment.yaml
        kubectl apply -f service.yaml
        kubectl apply -f ingress.yaml

        kubectl wait --for=condition=available --timeout=300s deployment/analytics-api -n ${namespace}
        kubectl wait --for=condition=available --timeout=300s deployment/analytics-web -n ${namespace}

        git checkout -- deployment.yaml
        """
    }
}
