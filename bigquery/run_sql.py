#!/usr/bin/env python3

import argparse
import time
from pathlib import Path

from google.cloud import bigquery

SQL_DIR = Path(__file__).resolve().parent / "sql"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--only", default="", help="run only files whose path contains this text")
    args = ap.parse_args()

    client = bigquery.Client(project=args.project)
    files = sorted(p for p in SQL_DIR.rglob("*.sql") if args.only in str(p))
    total_bytes = 0
    for f in files:
        sql = f.read_text(encoding="utf-8")
        t0 = time.time()
        job = client.query(sql)
        job.result()
        total_bytes += job.total_bytes_processed or 0
        print(f"  {f.relative_to(SQL_DIR)!s:55s} {time.time() - t0:5.1f}s")
    print(f"Done: {len(files)} statements, {total_bytes / 1e6:,.1f} MB processed "
          f"(free tier: 1,000,000 MB per month)")


if __name__ == "__main__":
    main()
