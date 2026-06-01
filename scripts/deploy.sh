#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ciembor@maciej-ciemborowicz.eu}"
REMOTE_DIR="${REMOTE_DIR:-/home/ciembor/polish-open-source-rank}"
SERVICE_NAME="${SERVICE_NAME:-polish-open-source-rank}"
IMAGE_NAME="${IMAGE_NAME:-localhost/polish-open-source-rank:latest}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://polish-open-source.pl}"
HEALTHCHECK_ATTEMPTS="${HEALTHCHECK_ATTEMPTS:-30}"
HEALTHCHECK_SLEEP_SECONDS="${HEALTHCHECK_SLEEP_SECONDS:-2}"
DEPLOY_ACTION="${1:-${DEPLOY_ACTION:-deploy}}"
RELEASE_NAME="${RELEASE_NAME:-$(git rev-parse --short HEAD)}"
IMAGE_REPOSITORY="${IMAGE_NAME%:*}"
PREVIOUS_IMAGE_NAME="${PREVIOUS_IMAGE_NAME:-${IMAGE_REPOSITORY}:previous}"
ROLLBACK_CANDIDATE_IMAGE_NAME="${ROLLBACK_CANDIDATE_IMAGE_NAME:-${IMAGE_REPOSITORY}:rollback-candidate}"
RELEASE_IMAGE_NAME="${RELEASE_IMAGE_NAME:-${IMAGE_REPOSITORY}:${RELEASE_NAME}}"

usage() {
  echo "usage: scripts/deploy.sh [deploy|rollback]" >&2
  exit 64
}

case "$DEPLOY_ACTION" in
  deploy|rollback)
    ;;
  *)
    usage
    ;;
esac

sync_checkout() {
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
}

if [ "$DEPLOY_ACTION" = "deploy" ]; then
  sync_checkout
fi

ssh "${REMOTE_HOST}" \
  "REMOTE_DIR='${REMOTE_DIR}' \
  SERVICE_NAME='${SERVICE_NAME}' \
  IMAGE_NAME='${IMAGE_NAME}' \
  PREVIOUS_IMAGE_NAME='${PREVIOUS_IMAGE_NAME}' \
  ROLLBACK_CANDIDATE_IMAGE_NAME='${ROLLBACK_CANDIDATE_IMAGE_NAME}' \
  RELEASE_IMAGE_NAME='${RELEASE_IMAGE_NAME}' \
  RELEASE_NAME='${RELEASE_NAME}' \
  PUBLIC_BASE_URL='${PUBLIC_BASE_URL}' \
  HEALTHCHECK_ATTEMPTS='${HEALTHCHECK_ATTEMPTS}' \
  HEALTHCHECK_SLEEP_SECONDS='${HEALTHCHECK_SLEEP_SECONDS}' \
  bash -s -- '${DEPLOY_ACTION}'" <<'REMOTE'
set -euo pipefail

action="$1"
deploy_state_dir="${REMOTE_DIR}/tmp/deploy"
current_release_file="${deploy_state_dir}/current-release"
previous_release_file="${deploy_state_dir}/previous-release"

mkdir -p "$deploy_state_dir"

image_exists() {
  sudo podman image inspect "$1" >/dev/null 2>&1
}

restart_app_services() {
  sudo systemctl restart "${SERVICE_NAME}"
  sudo systemctl restart "${SERVICE_NAME}-discord-bot"
}

smoke_check_once() {
  curl -fsSL -o /dev/null "http://127.0.0.1:9293/healthz" &&
    curl -fsSL -o /dev/null "${PUBLIC_BASE_URL}/healthz" &&
    curl -fsSL -o /dev/null "${PUBLIC_BASE_URL}/latest" &&
    curl -fsSL -o /dev/null "${PUBLIC_BASE_URL}/en/latest"
}

wait_for_smoke_checks() {
  local attempt
  for attempt in $(seq 1 "${HEALTHCHECK_ATTEMPTS}"); do
    if smoke_check_once; then
      return 0
    fi
    sleep "${HEALTHCHECK_SLEEP_SECONDS}"
  done

  return 1
}

report_running_jobs() {
  if sudo systemctl is-active --quiet "${SERVICE_NAME}-monthly.service"; then
    echo "${SERVICE_NAME}-monthly.service is active; leaving the running monthly job untouched"
  fi
  if sudo systemctl is-active --quiet "${SERVICE_NAME}-packages.service"; then
    echo "${SERVICE_NAME}-packages.service is active; leaving the running package job untouched"
  fi
}

install_units() {
  cd "${REMOTE_DIR}"
  for unit in \
    "${SERVICE_NAME}.service" \
    "${SERVICE_NAME}-crawl.service" \
    "${SERVICE_NAME}-crawl-resume.service" \
    "${SERVICE_NAME}-discord-bot.service" \
    "${SERVICE_NAME}-alerts.service" \
    "${SERVICE_NAME}-alerts.timer" \
    "${SERVICE_NAME}-monitor.service" \
    "${SERVICE_NAME}-monitor.timer" \
    "${SERVICE_NAME}-monthly.service" \
    "${SERVICE_NAME}-monthly.timer" \
    "${SERVICE_NAME}-packages.service" \
    "${SERVICE_NAME}-packages.timer"; do
    sudo install -m 0644 "deploy/${unit}" "/etc/systemd/system/${unit}"
  done

  sudo systemctl daemon-reload
  sudo systemctl enable "${SERVICE_NAME}.service"
  sudo systemctl enable "${SERVICE_NAME}-crawl-resume.service"
  sudo systemctl enable "${SERVICE_NAME}-discord-bot.service"
  sudo systemctl enable --now "${SERVICE_NAME}-alerts.timer"
  sudo systemctl enable --now "${SERVICE_NAME}-monitor.timer"
  sudo systemctl enable --now "${SERVICE_NAME}-monthly.timer"
  sudo systemctl enable --now "${SERVICE_NAME}-packages.timer"
}

deploy_release() {
  local previous_release=""

  install_units
  report_running_jobs

  if image_exists "${IMAGE_NAME}"; then
    sudo podman tag "${IMAGE_NAME}" "${PREVIOUS_IMAGE_NAME}"
    if [ -f "${current_release_file}" ]; then
      previous_release="$(cat "${current_release_file}")"
    fi
  fi

  cd "${REMOTE_DIR}"
  sudo podman build -t "${RELEASE_IMAGE_NAME}" .
  sudo podman tag "${RELEASE_IMAGE_NAME}" "${IMAGE_NAME}"
  restart_app_services

  if ! wait_for_smoke_checks; then
    echo "Deploy smoke checks failed; restoring previous image" >&2
    if image_exists "${PREVIOUS_IMAGE_NAME}"; then
      sudo podman tag "${PREVIOUS_IMAGE_NAME}" "${IMAGE_NAME}"
      restart_app_services
      wait_for_smoke_checks || true
    fi
    sudo systemctl status "${SERVICE_NAME}" --no-pager || true
    exit 1
  fi

  printf '%s\n' "${RELEASE_NAME}" > "${current_release_file}"
  if [ -n "${previous_release}" ]; then
    printf '%s\n' "${previous_release}" > "${previous_release_file}"
  else
    rm -f "${previous_release_file}"
  fi
}

rollback_release() {
  local current_release="unknown"
  local previous_release="unknown"

  if ! image_exists "${PREVIOUS_IMAGE_NAME}"; then
    echo "No previous image available for rollback" >&2
    exit 1
  fi

  if [ -f "${current_release_file}" ]; then
    current_release="$(cat "${current_release_file}")"
  fi
  if [ -f "${previous_release_file}" ]; then
    previous_release="$(cat "${previous_release_file}")"
  fi

  report_running_jobs
  sudo podman tag "${IMAGE_NAME}" "${ROLLBACK_CANDIDATE_IMAGE_NAME}"
  sudo podman tag "${PREVIOUS_IMAGE_NAME}" "${IMAGE_NAME}"
  restart_app_services

  if ! wait_for_smoke_checks; then
    echo "Rollback smoke checks failed; restoring the pre-rollback image" >&2
    sudo podman tag "${ROLLBACK_CANDIDATE_IMAGE_NAME}" "${IMAGE_NAME}"
    restart_app_services
    wait_for_smoke_checks || true
    sudo systemctl status "${SERVICE_NAME}" --no-pager || true
    exit 1
  fi

  sudo podman tag "${ROLLBACK_CANDIDATE_IMAGE_NAME}" "${PREVIOUS_IMAGE_NAME}"
  printf '%s\n' "${previous_release}" > "${current_release_file}"
  printf '%s\n' "${current_release}" > "${previous_release_file}"
  sudo podman image rm "${ROLLBACK_CANDIDATE_IMAGE_NAME}" >/dev/null 2>&1 || true
}

case "${action}" in
  deploy)
    deploy_release
    ;;
  rollback)
    rollback_release
    ;;
  *)
    echo "Unsupported deploy action: ${action}" >&2
    exit 64
    ;;
esac

sudo systemctl status "${SERVICE_NAME}" --no-pager
REMOTE
