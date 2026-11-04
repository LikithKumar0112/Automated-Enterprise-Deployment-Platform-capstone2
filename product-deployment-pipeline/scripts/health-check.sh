#!/bin/bash
# Polls a deployed endpoint's health path until it succeeds or attempts run out.
# Exits non-zero if the endpoint never becomes healthy.
# Usage: ./health-check.sh <base-url> [path] [max_attempts] [sleep_seconds] [host_header]
#   e.g. ./health-check.sh http://my-alb.amazonaws.com /health 30 10 app.example.com
set -u
URL="${1:-}"
PATH_="${2:-/health}"
MAX_ATTEMPTS="${3:-30}"
SLEEP_SECONDS="${4:-5}"
HOST_HEADER="${5:-}"

# A bare scheme means the ingress lookup returned nothing: that's a failure, not a skip.
if [[ -z "$URL" || "$URL" == "http://" || "$URL" == "https://" ]]; then
    echo "❌ No endpoint to check (URL is empty - has the Ingress got an address?)"
    echo "Usage: $0 <base-url> [path] [max_attempts] [sleep_seconds] [host_header]"
    exit 1
fi

CURL_ARGS=(-sf --max-time 10)
[[ -n "$HOST_HEADER" ]] && CURL_ARGS+=(-H "Host: ${HOST_HEADER}")

echo "Checking ${URL}${PATH_} ..."
for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
    if curl "${CURL_ARGS[@]}" "${URL}${PATH_}" > /dev/null; then
        echo "✅ Healthy after ${i} attempt(s)"
        exit 0
    fi
    echo "Attempt ${i}/${MAX_ATTEMPTS} failed, retrying in ${SLEEP_SECONDS}s..."
    [[ "$i" -lt "$MAX_ATTEMPTS" ]] && sleep "$SLEEP_SECONDS"
done
echo "❌ ${URL}${PATH_} not healthy after ${MAX_ATTEMPTS} attempts"
exit 1
