#!/usr/bin/env python3
import os
import sqlite3
import sys
from datetime import date, timedelta
from pathlib import Path


DEFAULT_DATABASE_URL = "sqlite://db/polish_open_source_rank.sqlite3"
REQUIRED_STATS_TABLES = [
    "user_monthly_stats",
    "repository_monthly_stats",
    "organization_monthly_stats",
    "organization_repository_monthly_stats",
]
ACTIVE_SCAN_STATUSES = ["pending", "processing", "failed"]


def main():
    root = Path.cwd()
    load_env_file(root / ".env.local")
    database_path = normalize_database_path(os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL), root)
    period_start = os.environ.get("PUBLISH_PERIOD_START", previous_month_start().isoformat())

    with sqlite3.connect(database_path) as connection:
        failures = verification_failures(connection, period_start)

    if failures:
        print(f"Snapshot {period_start} is not publishable: {'; '.join(failures)}", file=sys.stderr)
        return 75

    print(f"Snapshot {period_start} is publishable")
    return 0


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


def previous_month_start(today=None):
    today = today or date.today()
    first_day = today.replace(day=1)
    previous_month = first_day - timedelta(days=1)
    return previous_month.replace(day=1)


def verification_failures(connection, period_start):
    failures = []
    if not has_finished_monthly_run(connection, period_start):
        failures.append("monthly rankings are not finished")

    missing_stats = [table for table in REQUIRED_STATS_TABLES if not table_has_period(connection, table, period_start)]
    if missing_stats:
        failures.append(f"missing public stats: {', '.join(missing_stats)}")

    latest_run_status = scalar(
        connection,
        """
        SELECT status
        FROM package_crawl_runs
        WHERE period_start = ?
        ORDER BY datetime(started_at) DESC, id DESC
        LIMIT 1
        """,
        [period_start],
    )
    active_scans = scalar(
        connection,
        f"""
        SELECT COUNT(*)
        FROM package_repository_scans
        WHERE period_start = ?
          AND status IN ({placeholders(ACTIVE_SCAN_STATUSES)})
        """,
        [period_start, *ACTIVE_SCAN_STATUSES],
    )
    if latest_run_status != "finished" or active_scans:
        failures.append(
            f"package crawls are not finished: latest run is {latest_run_status or 'missing'}, {active_scans} active scans"
        )

    return failures


def has_finished_monthly_run(connection, period_start):
    return scalar(
        connection,
        "SELECT 1 FROM sync_runs WHERE period_start = ? AND status = 'finished' LIMIT 1",
        [period_start],
    ) == 1


def table_has_period(connection, table, period_start):
    return scalar(connection, f"SELECT 1 FROM {table} WHERE period_start = ? LIMIT 1", [period_start]) == 1


def scalar(connection, query, params=None):
    row = connection.execute(query, params or []).fetchone()
    return row[0] if row else None


def placeholders(values):
    return ", ".join("?" for _value in values)


if __name__ == "__main__":
    raise SystemExit(main())
