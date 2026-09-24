import argparse
import json
import socket
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = "https://custom.resbank.co.za/SarbWebApi/WebIndicators"

DEFAULT_CODES = ["MMRD002A", "MMRD000A", "EXCX135D"]

DEFAULT_OUT = Path(__file__).resolve().parent.parent / "datasets" 

USER_AGENT = "Mozilla/5.0 (compatible; dwh-student-project/1.0)"
DATE_KEYS = ("Period", "Date", "period", "date", "ValueDate")


def fetch(url, timeout, retries):
    """GET a URL and return the body as bytes. Retries network errors and 5xx."""
    request = urllib.request.Request(
        url, headers={"Accept": "application/json", "User-Agent": USER_AGENT}
    )
    last_error = None
    attempts = 0
    for attempt in range(1, retries + 1):
        attempts = attempt
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            last_error = error
            if 400 <= error.code < 500:  # client error: retrying won't help
                break
        except (urllib.error.URLError, socket.timeout, ConnectionError) as error:
            last_error = error
        if attempt < retries:
            time.sleep(2 ** attempt)
    raise RuntimeError(f"request failed after {attempts} attempt(s): {last_error}")


def parse_records(raw, label):
    """Decode JSON and return the list of observations, or raise ValueError."""
    try:
        data = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"{label}: response is not valid JSON ({error})")
    if isinstance(data, dict):  
        data = next((v for v in data.values() if isinstance(v, list)), None)
    if not isinstance(data, list) or not data:
        raise ValueError(f"{label}: no observations returned (is the code correct?)")
    return data


def date_range(records):
    """Return (first, last) date strings if the records carry a date field."""
    for key in DATE_KEYS:
        values = [str(r[key])[:10] for r in records if isinstance(r, dict) and r.get(key)]
        if values:
            return min(values), max(values)
    return None, None


def save_atomic(path, raw):
    """Write to a temp file then rename, so a failed run never leaves a half file."""
    temp = path.with_name(path.name + ".tmp")
    temp.write_bytes(raw)
    temp.replace(path)


def download_series(code, base_url, out_dir, timeout, retries):
    url = f"{base_url}/Shared/GetTimeseriesObservations/{code}"
    raw = fetch(url, timeout, retries)
    records = parse_records(raw, code)
    path = out_dir / f"{code}.json"
    save_atomic(path, raw)
    first, last = date_range(records)
    span = f"{first} to {last}" if first else "date field not found"
    print(f"  OK   {code:<10} {len(records):>7} records  {span}  -> {path}")


def list_exchange_rates(base_url, timeout, retries):
    """Print the codes SARB lists as exchange rates (from CurrentMarketRates)."""
    raw = fetch(f"{base_url}/CurrentMarketRates", timeout, retries)
    rows = parse_records(raw, "CurrentMarketRates")
    found = 0
    for item in rows:
        if not isinstance(item, dict):
            continue
        fields = {k.lower(): v for k, v in item.items()}
        name = str(fields.get("name") or "")
        code = str(fields.get("timeseriescode") or "")
        section = str(fields.get("sectionname") or "")
        if code and (name.lower().startswith("rand per") or "exchange" in section.lower()):
            print(f"  {code:<10} {name}")
            found += 1
    if not found:
        print("  No exchange-rate rows recognised. Fields in the first row:")
        print("  ", list(rows[0].keys()) if isinstance(rows[0], dict) else rows[0])
    return found


def main():
    parser = argparse.ArgumentParser(description="Download SARB time series as raw JSON.")
    parser.add_argument("--codes", nargs="+", default=DEFAULT_CODES,
                        help=f"SARB time series codes (default: {' '.join(DEFAULT_CODES)})")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"output folder (default: {DEFAULT_OUT})")
    parser.add_argument("--list-fx", action="store_true",
                        help="list rand exchange-rate codes and exit")
    parser.add_argument("--base-url", default=BASE_URL, help=argparse.SUPPRESS)
    parser.add_argument("--timeout", type=int, default=30, help="seconds per request")
    parser.add_argument("--retries", type=int, default=3, help="attempts per request")
    args = parser.parse_args()

    if args.list_fx:
        print("Exchange-rate codes listed by SARB:")
        try:
            found = list_exchange_rates(args.base_url, args.timeout, args.retries)
        except (RuntimeError, ValueError) as error:
            print(f"  FAIL {error}")
            return 1
        return 0 if found else 1

    args.out.mkdir(parents=True, exist_ok=True)
    print(f"Saving to {args.out}")
    failures = 0
    for code in args.codes:
        try:
            download_series(code, args.base_url, args.out, args.timeout, args.retries)
        except (RuntimeError, ValueError, OSError) as error:
            failures += 1
            print(f"  FAIL {code:<10} {error}")
    print(f"Done: {len(args.codes) - failures} succeeded, {failures} failed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
