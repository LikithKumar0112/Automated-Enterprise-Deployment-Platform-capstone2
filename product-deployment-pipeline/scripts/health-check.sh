#!/bin/bash
# Polls a deployed endpoint's health path until it succeeds or times out.
# Usage: ./health-check.sh <url> <path> [max_attempts] [sleep_seconds]
set -e
URL="$1"
PATH_="${2:-/health}"
MAX_ATTEMPTS="${3:-30}"
SLEEP_SECONDS="${4:-5}"

if [[ -z "$URL" ]]; then
    echo "Usage: $0 <url> <path> [max_attempts] [sleep_seconds]"
    exit 1
fi

echo "Checking https://${URL}${PATH_} ..."
for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
    if curl -sf "https://${URL}${PATH_}" > /dev/null; then
        echo "✅ Healthy after ${i} attempt(s)"
        exit 0
    fi
    echo "Attempt ${i}/${MAX_ATTEMPTS} failed, retrying in ${SLEEP_SECONDS}s..."
    sleep "$SLEEP_SECONDS"
done
echo "❌ Endpoint did not become healthy in time"
exit 1
