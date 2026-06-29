#!/usr/bin/env bash
set -euo pipefail
ENV=${1:-dev}
cd "environments/$ENV"
terraform plan -refresh=true -detailed-exitcode -no-color