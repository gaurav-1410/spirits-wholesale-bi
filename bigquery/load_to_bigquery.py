#!/usr/bin/env python3

import argparse
import json
from pathlib import Path

from google.api_core.exceptions import NotFound
from google.cloud import bigquery

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIR = ROOT / "bigquery" / "schemas"
DATASETS = {
    "raw": "Raw ERP and external data, loaded 1:1 from CSV",
    "staging": "Cleaned and standardised views on top of raw",
    "mart": "Star schema (facts & dimensions) consumed by Power BI",
    "dq": "Data quality & internal control checks (ICS)",
}
SOURCES = {  # table name -> sub folder in data/
    "salesperson": "erp", "customer": "erp", "vendor": "erp", "item": "erp",
    "sales_invoice_header": "erp", "sales_invoice_line": "erp",
    "purchase_header": "erp", "purchase_line": "erp",
    "item_ledger_entry": "erp", "cust_ledger_entry": "erp",
    "fx_rates_daily": "external", "public_holidays_de_hb": "external", "excise_duty_rates": "external",
}


def ensure_datasets(client: bigquery.Client, location: str) -> None:
    for name, desc in DATASETS.items():
        ds_id = f"{client.project}.{name}"
        try:
            client.get_dataset(ds_id)
            print(f"dataset {name:8s} exists")
        except NotFound:
            ds = bigquery.Dataset(ds_id)
            ds.location = location
            ds.description = desc
            client.create_dataset(ds)
            print(f"dataset {name:8s} created ({location})")


def load_table(client: bigquery.Client, table: str, csv_path: Path) -> None:
    schema = [bigquery.SchemaField(f["name"], f["type"], mode=f.get("mode", "NULLABLE"),
                                   description=f.get("description"))
              for f in json.loads((SCHEMA_DIR / f"{table}.json").read_text(encoding="utf-8"))]
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        schema=schema,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        allow_quoted_newlines=True,
        encoding="UTF-8",
    )
    with open(csv_path, "rb") as fh:
        job = client.load_table_from_file(fh, f"{client.project}.raw.{table}", job_config=job_config)
    job.result()
    rows = client.get_table(f"{client.project}.raw.{table}").num_rows
    print(f"  raw.{table:24s} {rows:>9,} rows")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="Google Cloud project ID")
    ap.add_argument("--location", default="EU", help="dataset location (default EU)")
    ap.add_argument("--data-dir", default=str(ROOT / "data"))
    args = ap.parse_args()

    client = bigquery.Client(project=args.project)
    ensure_datasets(client, args.location)
    print("Loading CSV files ...")
    for table, sub in SOURCES.items():
        load_table(client, table, Path(args.data_dir) / sub / f"{table}.csv")
    print("Done. Next step: python bigquery/run_sql.py --project", args.project)


if __name__ == "__main__":
    main()
