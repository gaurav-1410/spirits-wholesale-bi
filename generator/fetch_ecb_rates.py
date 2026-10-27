#!/usr/bin/env python3

import csv
import io
import urllib.request
from pathlib import Path

URL = ("https://data-api.ecb.europa.eu/service/data/EXR/D.USD+GBP.EUR.SP00.A"
       "?startPeriod=2022-10-01&endPeriod=2026-09-30&format=csvdata")
OUT = Path(__file__).resolve().parents[1] / "data" / "external" / "fx_rates_ecb.csv"


def main() -> None:
    with urllib.request.urlopen(URL, timeout=60) as resp:
        text = resp.read().decode("utf-8")
    rows = [(r["TIME_PERIOD"], r["CURRENCY"], r["OBS_VALUE"])
            for r in csv.DictReader(io.StringIO(text)) if r.get("OBS_VALUE")]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["Rate_Date", "Currency_Code", "Exchange_Rate"])
        w.writerows(sorted(rows))
    print(f"saved {len(rows)} rates to {OUT}")


if __name__ == "__main__":
    main()
