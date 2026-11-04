#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"

ingress_host() {
    kubectl get ingress "$1" -n analytics -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
}

"$SCRIPT_DIR/health-check.sh" "http://$(ingress_host analytics-api)" /actuator/health 30 10 api.analytics.company.com
"$SCRIPT_DIR/health-check.sh" "http://$(ingress_host analytics-web)" /health 30 10 app.analytics.company.com
