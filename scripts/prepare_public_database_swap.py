#!/usr/bin/env python3
"""Prepare a stopped public SQLite database for replacement.

An old WAL can replay its page count onto the new file after an atomic rename,
truncating the snapshot. The caller must stop web readers before this runs.
"""

import sqlite3
import sys
from pathlib import Path


def prepare(path):
    if not path.exists():
        return

    connection = sqlite3.connect(path)
    try:
        busy, _, _ = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if busy:
            raise RuntimeError(f"cannot checkpoint public database: {path}")
    finally:
        connection.close()

    for suffix in ("-wal", "-shm"):
        Path(f"{path}{suffix}").unlink(missing_ok=True)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]))
