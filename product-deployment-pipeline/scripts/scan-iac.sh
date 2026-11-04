#!/bin/bash
# Fails on any Terraform finding not listed in .checkov.baseline
set -euo pipefail

docker run --rm -v "$PWD/product-infrastructure:/iac" bridgecrew/checkov:3.3.19 \
    -d /iac --framework terraform --compact --quiet --baseline /iac/.checkov.baseline
