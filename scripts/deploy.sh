#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ciembor@maciej-ciemborowicz.eu}"
REMOTE_DIR="${REMOTE_DIR:-/home/ciembor/polish-github-rank}"
SERVICE_NAME="${SERVICE_NAME:-polish-github-rank}"
IMAGE_NAME="${IMAGE_NAME:-localhost/polish-github-rank:latest}"

rsync -az --delete \
  --exclude '.env.local' \
  --exclude '.git/' \
  --exclude 'AGENTS.md' \
  --exclude 'coverage/' \
  --exclude 'db/*.sqlite3' \
  --exclude 'db/*.sqlite3-*' \
  --exclude 'log/' \
  --exclude 'tmp/' \
  --exclude 'vendor/bundle/' \
  ./ "${REMOTE_HOST}:${REMOTE_DIR}/"

ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && podman build -t ${IMAGE_NAME} . && sudo systemctl restart ${SERVICE_NAME} && sudo systemctl status ${SERVICE_NAME} --no-pager"
