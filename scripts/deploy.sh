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
  --exclude 'db/' \
  --exclude 'log/' \
  --exclude 'tmp/' \
  --exclude 'vendor/bundle/' \
  ./ "${REMOTE_HOST}:${REMOTE_DIR}/"

ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && \
  sudo install -m 0644 deploy/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-crawl.service /etc/systemd/system/${SERVICE_NAME}-crawl.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-crawl-resume.service /etc/systemd/system/${SERVICE_NAME}-crawl-resume.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-discord-bot.service /etc/systemd/system/${SERVICE_NAME}-discord-bot.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-alerts.service /etc/systemd/system/${SERVICE_NAME}-alerts.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-alerts.timer /etc/systemd/system/${SERVICE_NAME}-alerts.timer && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monitor.service /etc/systemd/system/${SERVICE_NAME}-monitor.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monitor.timer /etc/systemd/system/${SERVICE_NAME}-monitor.timer && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monthly.service /etc/systemd/system/${SERVICE_NAME}-monthly.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-monthly.timer /etc/systemd/system/${SERVICE_NAME}-monthly.timer && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-packages.service /etc/systemd/system/${SERVICE_NAME}-packages.service && \
  sudo install -m 0644 deploy/${SERVICE_NAME}-packages.timer /etc/systemd/system/${SERVICE_NAME}-packages.timer && \
  sudo systemctl daemon-reload && \
  sudo systemctl enable ${SERVICE_NAME}.service && \
  sudo systemctl enable ${SERVICE_NAME}-crawl-resume.service && \
  sudo systemctl enable ${SERVICE_NAME}-discord-bot.service && \
  sudo systemctl enable --now ${SERVICE_NAME}-alerts.timer && \
  sudo systemctl enable --now ${SERVICE_NAME}-monitor.timer && \
  sudo systemctl enable --now ${SERVICE_NAME}-monthly.timer && \
  sudo systemctl enable --now ${SERVICE_NAME}-packages.timer && \
  if sudo systemctl is-active --quiet ${SERVICE_NAME}-monthly.service; then echo '${SERVICE_NAME}-monthly.service is active; leaving the running monthly job untouched'; fi && \
  if sudo systemctl is-active --quiet ${SERVICE_NAME}-packages.service; then echo '${SERVICE_NAME}-packages.service is active; leaving the running package job untouched'; fi && \
  sudo podman build -t ${IMAGE_NAME} . && \
  sudo systemctl restart ${SERVICE_NAME} && \
  sudo systemctl restart ${SERVICE_NAME}-discord-bot && \
  sudo systemctl status ${SERVICE_NAME} --no-pager"
