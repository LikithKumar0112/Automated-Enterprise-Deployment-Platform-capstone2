#!/bin/bash
# Sends a formatted Slack message via an incoming webhook.
# Usage: ./notify-slack.sh <status> <message> [webhook_url]
set -e
STATUS="${1:?status is required (SUCCESS|FAILED)}"
MESSAGE="${2:?message is required}"
WEBHOOK_URL="${3:-$SLACK_WEBHOOK_URL}"

if [[ -z "$WEBHOOK_URL" ]]; then
    echo "No Slack webhook configured, skipping notification"
    exit 0
fi
ICON="✅"
[[ "$STATUS" == "FAILED" ]] && ICON="❌"
curl -sf -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"${ICON} Deployment ${STATUS}: ${MESSAGE}\"}" "$WEBHOOK_URL"
