#!/usr/bin/env python3
import json
import math
import os
import socket
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib import error as urllib_error
from urllib import parse as urllib_parse
from urllib import request as urllib_request


HTTP_REQUEST_EVENT = "http_request"
SQLITE_WRITE_RETRY_EVENT = "sqlite_write_retry"
JOURNAL_UNITS = [
    "polish-open-source-rank.service",
    "polish-open-source-rank-monthly.service",
    "polish-open-source-rank-packages.service",
    "polish-open-source-rank-crawl.service",
    "polish-open-source-rank-crawl-resume.service",
    "polish-open-source-rank-discord-bot.service",
]
DEFAULT_STATE_PATH = "tmp/production-alert-state.json"
DEFAULT_DATABASE_URL = "sqlite://db/polish_open_source_rank.sqlite3"
DEFAULTS = {
    "PRODUCTION_ALERT_JOB_STALE_MINUTES": 30,
    "PRODUCTION_ALERT_LOG_WINDOW_MINUTES": 10,
    "PRODUCTION_ALERT_HTTP_5XX_THRESHOLD": 5,
    "PRODUCTION_ALERT_HTTP_MIN_REQUESTS": 20,
    "PRODUCTION_ALERT_P95_LATENCY_MS_THRESHOLD": 1000,
    "PRODUCTION_ALERT_SQLITE_RETRY_THRESHOLD": 10,
}


def main():
    root = Path.cwd()
    load_env_file(root / ".env.local")
    now = datetime.now(timezone.utc)
    database_path = normalize_database_path(os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL), root)
    log_window_minutes = env_int("PRODUCTION_ALERT_LOG_WINDOW_MINUTES")
    events = collect_structured_events(log_window_minutes, now)

    with sqlite3.connect(database_path) as connection:
        connection.row_factory = sqlite3.Row
        jobs = job_snapshots(connection)

    web_metrics = summarize_web_requests(events)
    sqlite_metrics = summarize_sqlite_retries(events)
    alerts = evaluate_alerts(jobs, web_metrics, sqlite_metrics, now)
    state_path = root / os.environ.get("PRODUCTION_ALERT_STATE_PATH", DEFAULT_STATE_PATH)
    previous_alerts = load_state(state_path)
    delivery = sync_sentry_alerts(previous_alerts, alerts)
    save_state(state_path, alerts)

    summary = {
        "generated_at": now.isoformat(),
        "alerts": alerts,
        "delivery": delivery,
        "web_metrics": web_metrics,
        "sqlite_metrics": sqlite_metrics,
    }
    print(json.dumps(summary))


def load_env_file(path):
    if not path.is_file():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def normalize_database_path(raw_value, root):
    raw_path = (raw_value or DEFAULT_DATABASE_URL).removeprefix("sqlite://")
    path = Path(raw_path)
    return str(path if path.is_absolute() else root / path)


def env_int(name):
    return int(os.environ.get(name, DEFAULTS[name]))


def collect_structured_events(window_minutes, now):
    since = (now - timedelta(minutes=window_minutes)).isoformat()
    journalctl = os.environ.get("PRODUCTION_ALERT_JOURNALCTL", "journalctl")
    command = [journalctl, "-o", "cat", "--since", since]
    for unit in JOURNAL_UNITS:
        command.extend(["-u", unit])
    result = subprocess.run(command, capture_output=True, check=True, text=True)
    return [event for event in (parse_structured_event(line) for line in result.stdout.splitlines()) if event]


def parse_structured_event(line):
    stripped = line.strip()
    if not stripped:
        return None

    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None

    event_name = payload.get("event")
    if event_name not in (HTTP_REQUEST_EVENT, SQLITE_WRITE_RETRY_EVENT):
        return None
    return payload


def job_snapshots(connection):
    return {
        "monthly": monthly_snapshot(connection),
        "packages": package_snapshot(connection),
    }


def monthly_snapshot(connection):
    row = connection.execute(
        """
        SELECT period_start, status, started_at, finished_at, error
        FROM sync_runs
        ORDER BY datetime(started_at) DESC, period_start DESC
        LIMIT 1
        """
    ).fetchone()
    return build_job_snapshot(connection, "monthly", row) if row else None


def package_snapshot(connection):
    if not table_exists(connection, "package_crawl_runs"):
        return None
    row = connection.execute(
        """
        SELECT id, period_start, ecosystem, status, started_at, finished_at, error
        FROM package_crawl_runs
        ORDER BY datetime(started_at) DESC, id DESC
        LIMIT 1
        """
    ).fetchone()
    return build_job_snapshot(connection, "packages", row) if row else None


def build_job_snapshot(connection, kind, row):
    snapshot = dict(row)
    snapshot["kind"] = kind
    snapshot["last_work_event_at"] = latest_work_event_at(
        connection,
        kind,
        snapshot["period_start"],
        snapshot["started_at"],
        snapshot.get("ecosystem"),
    )
    return snapshot


def latest_work_event_at(connection, job_kind, period_start, started_at, ecosystem):
    query = """
        SELECT finished_at
        FROM job_work_events
        WHERE job_kind = ?
          AND period_start = ?
          AND datetime(finished_at) >= datetime(?)
    """
    params = [job_kind, period_start, started_at]
    if ecosystem:
        query += " AND ecosystem = ?"
        params.append(ecosystem)
    query += " ORDER BY datetime(finished_at) DESC, id DESC LIMIT 1"
    row = connection.execute(query, params).fetchone()
    return row["finished_at"] if row else None


def table_exists(connection, name):
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [name],
    ).fetchone()
    return row is not None


def summarize_web_requests(events):
    requests = [event for event in events if event.get("event") == HTTP_REQUEST_EVENT]
    latencies = sorted(float(event.get("latency_ms", 0.0)) for event in requests)
    return {
        "request_count": len(requests),
        "http_5xx_count": sum(1 for event in requests if int(event.get("status", 0)) >= 500),
        "p95_latency_ms": percentile(latencies, 95),
    }


def summarize_sqlite_retries(events):
    retries = [event for event in events if event.get("event") == SQLITE_WRITE_RETRY_EVENT]
    return {
        "retry_count": len(retries),
        "lock_wait_ms": round(sum(float(event.get("lock_wait_ms", 0.0)) for event in retries), 1),
        "backoff_ms": round(sum(float(event.get("backoff_ms", 0.0)) for event in retries), 1),
    }


def percentile(values, rank):
    if not values:
        return None
    index = max(0, math.ceil(len(values) * rank / 100.0) - 1)
    return round(values[index], 1)


def evaluate_alerts(jobs, web_metrics, sqlite_metrics, now):
    alerts = []
    stale_minutes = env_int("PRODUCTION_ALERT_JOB_STALE_MINUTES")

    for kind, job in jobs.items():
        if not job:
            continue
        alerts.extend(job_alerts(kind, job, now, stale_minutes))

    if web_metrics["http_5xx_count"] >= env_int("PRODUCTION_ALERT_HTTP_5XX_THRESHOLD"):
        alerts.append(
            {
                "key": "http_5xx_spike",
                "summary": f"HTTP 5xx spiked to {web_metrics['http_5xx_count']} responses in the recent window",
                "details": {
                    "request_count": web_metrics["request_count"],
                    "http_5xx_count": web_metrics["http_5xx_count"],
                },
            }
        )

    enough_requests = web_metrics["request_count"] >= env_int("PRODUCTION_ALERT_HTTP_MIN_REQUESTS")
    slow_p95 = web_metrics["p95_latency_ms"] is not None and web_metrics["p95_latency_ms"] >= env_int(
        "PRODUCTION_ALERT_P95_LATENCY_MS_THRESHOLD"
    )
    if enough_requests and slow_p95:
        alerts.append(
            {
                "key": "http_p95_latency_high",
                "summary": f"HTTP p95 latency reached {web_metrics['p95_latency_ms']} ms in the recent window",
                "details": {
                    "request_count": web_metrics["request_count"],
                    "p95_latency_ms": web_metrics["p95_latency_ms"],
                },
            }
        )

    if sqlite_metrics["retry_count"] >= env_int("PRODUCTION_ALERT_SQLITE_RETRY_THRESHOLD"):
        alerts.append(
            {
                "key": "sqlite_retry_spike",
                "summary": f"SQLite write retries spiked to {sqlite_metrics['retry_count']} events in the recent window",
                "details": sqlite_metrics,
            }
        )

    return sorted(alerts, key=lambda alert: alert["key"])


def job_alerts(kind, job, now, stale_minutes):
    alerts = []
    label = kind if not job.get("ecosystem") else f"{kind}:{job['ecosystem']}"

    if job["status"] == "failed":
        alerts.append(
            {
                "key": f"{kind}_failed",
                "summary": f"{label} failed for period {job['period_start']}",
                "details": {
                    "period_start": job["period_start"],
                    "status": job["status"],
                    "error": job.get("error"),
                    "started_at": job["started_at"],
                    "finished_at": job.get("finished_at"),
                },
            }
        )

    if job["status"] != "running":
        return alerts

    progress_at = job.get("last_work_event_at") or job["started_at"]
    stale_seconds = (now - parse_utc(progress_at)).total_seconds()
    if stale_seconds < stale_minutes * 60:
        return alerts

    alerts.append(
        {
            "key": f"{kind}_stalled",
            "summary": f"{label} has not recorded a work event for {round(stale_seconds / 60.0, 1)} minutes",
            "details": {
                "period_start": job["period_start"],
                "status": job["status"],
                "started_at": job["started_at"],
                "last_work_event_at": job.get("last_work_event_at"),
                "stale_minutes": round(stale_seconds / 60.0, 1),
            },
        }
    )
    return alerts


def parse_utc(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def load_state(path):
    if not path.is_file():
        return []
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("alerts", [])


def save_state(path, alerts):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"alerts": alerts}
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def sync_sentry_alerts(previous_alerts, current_alerts):
    previous = {alert["key"]: alert for alert in previous_alerts}
    current = {alert["key"]: alert for alert in current_alerts}
    sent = []

    for key, alert in current.items():
        if previous.get(key) == alert:
            continue
        if deliver_sentry_event(alert, state="firing"):
            sent.append(f"{key}:firing")

    for key, alert in previous.items():
        if key in current:
            continue
        if deliver_sentry_event(alert, state="resolved"):
            sent.append(f"{key}:resolved")

    return {"sentry_events": sent}


def deliver_sentry_event(alert, state):
    dsn = os.environ.get("SENTRY_DSN", "").strip()
    if not dsn:
        return False

    payload = {
        "event_id": uuid.uuid4().hex,
        "message": sentry_message(alert, state),
        "level": "error" if state == "firing" else "info",
        "logger": "production-alert-monitor",
        "server_name": socket.gethostname(),
        "fingerprint": [alert["key"]],
        "tags": {
            "monitor": "production-alert",
            "alert_key": alert["key"],
            "alert_state": state,
        },
        "extra": alert.get("details", {}),
    }
    post_sentry_event(dsn, payload)
    return True


def sentry_message(alert, state):
    prefix = "resolved" if state == "resolved" else "firing"
    return f"[{prefix}] {alert['summary']}"


def post_sentry_event(dsn, payload):
    parsed = urllib_parse.urlparse(dsn)
    public_key = parsed.username
    secret_key = parsed.password
    project_id = parsed.path.rsplit("/", 1)[-1]
    endpoint = f"{parsed.scheme}://{parsed.hostname}/api/{project_id}/store/"
    if parsed.port:
        endpoint = f"{parsed.scheme}://{parsed.hostname}:{parsed.port}/api/{project_id}/store/"

    auth_parts = [
        "Sentry sentry_version=7",
        f"sentry_key={public_key}",
        "sentry_client=production-alert-monitor/1.0",
    ]
    if secret_key:
        auth_parts.append(f"sentry_secret={secret_key}")

    request = urllib_request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Sentry-Auth": ", ".join(auth_parts),
        },
        method="POST",
    )
    try:
        with urllib_request.urlopen(request, timeout=10):
            return
    except urllib_error.URLError as exc:
        raise RuntimeError(f"failed to deliver Sentry event: {exc}") from exc


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "class": exc.__class__.__name__}), file=sys.stderr)
        raise
