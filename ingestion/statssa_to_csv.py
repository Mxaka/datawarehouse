import argparse
import csv
import re
import sys
from pathlib import Path

HEADER_COLUMNS = ["H01", "H02", "H03", "H04", "H05", "H06", "H13", "H15", "H16", "H17", "H18", "H23", "H24", "H25"]

DEFAULT_OUT = Path(__file__).resolve().parent.parent / "datasets" / "source_statssa"
HEADER_LINE = re.compile(r"^(H\d+):\s?(.*)$")
NUMBER = re.compile(r"^-?\d+(\.\d+)?$")

def read_text(path):
    raw = path.read_bytes()

    try:
        return raw.decode("utf-8-sig")
    except:
        return raw.decode("cp1252")

def parse_file(path):
    series = []
    current = None

    for number, line in enumerate(read_text(path).splitlines(), start=1):
        if not line.strip():
            continue

        match = HEADER_LINE.match(line)

        if match:
            code, text = match.group(1), match.group(2).strip()

            if code not in HEADER_COLUMNS:
                raise ValueError(f"{path.name} line {number}: unkown header {code}. ")

            if code == "H01":
                current = {"headers": {}, "values": []}
                series.append(current)

            if current is None:
                raise ValueError(f"{path.name} line {number}: header before any H01 line")

            current["headers"][code] = text 
        else:
            value = line.strip()

            if current is None or not NUMBER.match(value):
                raise ValueError(f"{path.name} line {number}: expected a number, got {value!r}")

            current["values"].append(value)

    return series

def main():
    parser = argparse.ArgumentParser(description="Flatten Stats SA ASCII time series into CSVs.")
    parser.add_argument("inputs", nargs="+", type=Path, help="one or more Stats SA ASCII .txt files")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output folder (default: {DEFAULT_OUT})")
    args = parser.parse_args()

    all_series = []
    for path in args.inputs:
        if not path.is_file():
            print(f"FAIL {path}: file not found")
            return 1
        try:
            series = parse_file(path)
        except ValueError as error:
            print(f"FAIL {error}")
            return 1
        if not series:
            print(f"FAIL {path.name}: no series found (is this a Stats SA ASCII file?)")
            return 1
        print(f"  {path.name}: {len(series)} series, {sum(len(s['values']) for s in series)} values")
        all_series.extend(series)

    seen = set()
    for s in all_series:
        key = (s["headers"].get("H01", ""), s["headers"].get("H03", ""))
        if not key[1]:
            print(f"FAIL series in {key[0]} has no H03 (series code)")
            return 1
        if key in seen:
            print(f"FAIL duplicate series {key}")
            return 1
        seen.add(key)
        if not s["values"]:
            print(f"FAIL series {key} has no values")
            return 1

    args.out.mkdir(parents=True, exist_ok=True)
    series_path = args.out / "statssa_series.csv"
    values_path = args.out / "statssa_values.csv"
    with series_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow([c.lower() for c in HEADER_COLUMNS])
        for s in all_series:
            writer.writerow([s["headers"].get(c, "") for c in HEADER_COLUMNS])
    value_rows = 0
    with values_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["publication", "series_code", "obs_seq", "obs_value"])
        for s in all_series:
            for seq, value in enumerate(s["values"], start=1):
                writer.writerow([s["headers"]["H01"], s["headers"]["H03"], seq, value])
                value_rows += 1
    print(f"Wrote {len(all_series)} rows -> {series_path}")
    print(f"Wrote {value_rows} rows -> {values_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())