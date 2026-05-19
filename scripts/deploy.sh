#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ciembor@maciej-ciemborowicz.eu}"
REMOTE_DIR="${REMOTE_DIR:-/home/ciembor/polish-open-source-rank}"
SERVICE_NAME="${SERVICE_NAME:-polish-open-source-rank}"
IMAGE_NAME="${IMAGE_NAME:-localhost/polish-open-source-rank:latest}"

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

ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && \
  sudo install -m 0644 deploy/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-discord-bot.service /etc/systemd/system/${SERVICE_NAME}-discord-bot.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monthly.service /etc/systemd/system/${SERVICE_NAME}-monthly.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monthly.timer /etc/systemd/system/${SERVICE_NAME}-monthly.timer && \
  sudo install -m 0644 deploy/nginx-${SERVICE_NAME}.conf /etc/nginx/snippets/${SERVICE_NAME}.conf && \
  sudo systemctl daemon-reload && \
  sudo nginx -t && \
  sudo systemctl enable ${SERVICE_NAME}.service && \
  sudo systemctl enable ${SERVICE_NAME}-discord-bot.service && \
  sudo systemctl enable --now ${SERVICE_NAME}-monthly.timer && \
  sudo systemctl reload nginx && \
  sudo podman build -t ${IMAGE_NAME} . && \
  sudo systemctl restart ${SERVICE_NAME} && \
  sudo systemctl restart ${SERVICE_NAME}-discord-bot && \
  sudo systemctl status ${SERVICE_NAME} --no-pager"
