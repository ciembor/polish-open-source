#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="${REMOTE_DIR:-/home/ciembor/polish-open-source-rank}"
SERVICE_NAME="${SERVICE_NAME:-polish-open-source-rank}"
CRAWL_ENV_FILE="${CRAWL_ENV_FILE:-${REMOTE_DIR}/.crawl.env}"

args="$*"
escaped_args=${args//\'/\'\\\'\'}

printf "CRAWL_ARGS='%s'\n" "${escaped_args}" | sudo tee "${CRAWL_ENV_FILE}" >/dev/null
sudo systemctl start "${SERVICE_NAME}-crawl.service"
