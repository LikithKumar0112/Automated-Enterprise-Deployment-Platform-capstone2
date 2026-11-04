#!/bin/bash
# Builds the api-secrets Kubernetes Secret from AWS Secrets Manager, so real
# values never live in Git. Fails if a value is missing rather than deploying
# with a placeholder. Set the values once per environment; see docs/runbooks.md.
# Usage: ./sync-secrets.sh <environment> [namespace]
set -euo pipefail
ENVIRONMENT="${1:?environment is required}"
NAMESPACE="${2:-analytics}"
PREFIX="analytics-${ENVIRONMENT}"

read_json() {
    aws secretsmanager get-secret-value --secret-id "${PREFIX}/$1" --query SecretString --output text
}

# Prints KEY=value lines, failing if any key is absent or empty.
to_env() {
    local json="$1"; shift
    local key value
    for key in "$@"; do
        value="$(jq -er --arg k "$key" '.[$k] // empty | select(length > 0)' <<<"$json")" || {
            echo "❌ $key is missing from Secrets Manager for ${ENVIRONMENT}" >&2
            return 1
        }
        printf '%s=%s\n' "$key" "$value"
    done
}

db_env="$(to_env "$(read_json db-credentials)" DB_USERNAME DB_PASSWORD DB_URL)"
api_env="$(to_env "$(read_json api-keys)" JWT_SIGNING_KEY)"

printf '%s\n%s\n' "$db_env" "$api_env" \
    | kubectl create secret generic api-secrets -n "$NAMESPACE" --from-env-file=/dev/stdin --dry-run=client -o yaml \
    | kubectl apply -f -
echo "✅ api-secrets synced from Secrets Manager (${PREFIX}/*)"
