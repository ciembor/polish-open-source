#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/ciembor/polish-open-source-rank}"
LOG_FILE="${LOG_FILE:-${APP_DIR}/log/server-health.log}"

mkdir -p "$(dirname "${LOG_FILE}")"

{
  printf '\n=== %s ===\n' "$(date --iso-8601=seconds)"
  hostname
  uptime
  free -h
  df -h /

  printf '\n--- services ---\n'
  systemctl --no-pager --plain --quiet is-active polish-open-source-rank.service && echo 'web=active' || echo 'web=inactive'
  systemctl --no-pager --plain --quiet is-active polish-open-source-rank-monthly.service && echo 'monthly=active' || echo 'monthly=inactive'
  systemctl --no-pager --plain --quiet is-active polish-open-source-rank-packages.service && echo 'packages=active' || echo 'packages=inactive'

  printf '\n--- containers ---\n'
  podman stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}' || true

  printf '\n--- top cpu ---\n'
  ps -eo pid,ppid,stat,pcpu,pmem,rss,comm,args --sort=-pcpu | head -20

  printf '\n--- top memory ---\n'
  ps -eo pid,ppid,stat,pcpu,pmem,rss,comm,args --sort=-rss | head -20

  printf '\n--- recent nginx upstream errors ---\n'
  tail -200 /var/log/nginx/error.log 2>/dev/null | grep -E 'polish-open-source\.pl|127\.0\.0\.1:9293|upstream' | tail -20 || true
} >> "${LOG_FILE}"

tail -n 5000 "${LOG_FILE}" > "${LOG_FILE}.tmp"
mv "${LOG_FILE}.tmp" "${LOG_FILE}"
