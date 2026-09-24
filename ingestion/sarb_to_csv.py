import argparse
import csv
import json
import sys
from pathlib import Path

DEFAULT_OUT = Path(__file__).resolve().parent.parent / "datasets" / "source_sarb"
REQUIRED_KEYS = ("Period", "Timeseries", "Description", "Value")


def parse_file(path):
    """Return (series_code, name, description, [(date, value), ...])."""
    series_code = path.stem
    try:
        records = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"{path.name}: not valid JSON ({error})")
    if not isinstance(records, list) or not records:
        raise ValueError(f"{path.name}: expected a non-empty JSON array of observations")

    names, descriptions, rows, seen_dates = set(), set(), [], set()
    for i, record in enumerate(records):
        if not isinstance(record, dict) or not all(k in record for k in REQUIRED_KEYS):
            raise ValueError(f"{path.name} record {i}: missing one of {REQUIRED_KEYS}")
        period = str(record["Period"])
        date = period[:10]
        if len(date) != 10 or date[4] != "-" or date[7] != "-":
            raise ValueError(f"{path.name} record {i}: unexpected Period format {period!r}")
        if date in seen_dates:
            raise ValueError(f"{path.name}: duplicate observation date {date}")
        seen_dates.add(date)
        names.add(str(record["Timeseries"]).strip())
        descriptions.add(str(record["Description"]).strip())
        rows.append((date, record["Value"]))

    if len(names) != 1:
        raise ValueError(f"{path.name}: series name is not consistent across rows: {names}")
    if len(descriptions) != 1:
        raise ValueError(f"{path.name}: description is not consistent across rows: {descriptions}")

    rows.sort()
    return series_code, names.pop(), descriptions.pop(), rows


def main():
    parser = argparse.ArgumentParser(description="Flatten saved SARB JSON files into CSVs.")
    parser.add_argument("inputs", nargs="+", type=Path, help="one or more SARB .json files")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output folder (default: {DEFAULT_OUT})")
    args = parser.parse_args()

    series_rows, obs_rows, seen_codes = [], [], set()
    for path in args.inputs:
        if not path.is_file():
            print(f"FAIL {path}: file not found")
            return 1
        try:
            code, name, description, rows = parse_file(path)
        except ValueError as error:
            print(f"FAIL {error}")
            return 1
        if code in seen_codes:
            print(f"FAIL duplicate series code {code} (from {path.name})")
            return 1
        seen_codes.add(code)
        series_rows.append((code, name, description))
        obs_rows.extend((code, date, value) for date, value in rows)
        print(f"  {path.name}: series {code} ({name}), {len(rows)} observations, "
              f"{rows[0][0]} to {rows[-1][0]}")

    args.out.mkdir(parents=True, exist_ok=True)
    series_path = args.out / "sarb_series.csv"
    obs_path = args.out / "sarb_observations.csv"
    with series_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["series_code", "timeseries_name", "description"])
        writer.writerows(series_rows)
    with obs_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["series_code", "obs_date", "obs_value"])
        writer.writerows(obs_rows)
    print(f"Wrote {len(series_rows)} rows -> {series_path}")
    print(f"Wrote {len(obs_rows)} rows -> {obs_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())