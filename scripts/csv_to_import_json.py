#!/usr/bin/env python3
"""Convert a CSV roster to the input for the authenticated import_students RPC.

Never commit real student rosters; this program only converts/validates locally.
"""
import argparse
import csv
import json
import re
from pathlib import Path

HEADERS = ["student_id", "full_name", "program_code", "year_level"]
ID = re.compile(r"[A-Za-z0-9-]{1,64}\Z")
PROGRAM = re.compile(r"[A-Z0-9-]{2,32}\Z")


def convert(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh, strict=True)
        if reader.fieldnames != HEADERS:
            raise ValueError(f"Expected CSV headers in this order: {','.join(HEADERS)}")
        records, seen = [], set()
        for line, row in enumerate(reader, start=2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f"Line {line}: wrong number of columns")
            sid = row["student_id"].strip()
            name = row["full_name"].strip()
            program = row["program_code"].strip()
            year = row["year_level"].strip()
            if not ID.fullmatch(sid) or not (1 <= len(name) <= 160):
                raise ValueError(f"Line {line}: invalid student ID or name")
            if not PROGRAM.fullmatch(program) or year not in {"1", "2", "3", "4", "5", "6"}:
                raise ValueError(f"Line {line}: invalid program or year level")
            if sid in seen:
                raise ValueError(f"Line {line}: duplicate student ID {sid!r}")
            seen.add(sid)
            records.append(dict(student_id=sid, full_name=name,
                                program_code=program, year_level=int(year)))
            if len(records) > 1000:
                raise ValueError("Maximum 1000 students per import")
        if not records:
            raise ValueError("Roster cannot be empty")
    return {"rows": records}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_file", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(convert(args.csv_file), ensure_ascii=False))
    except (ValueError, csv.Error) as exc:
        parser.exit(1, f"Roster rejected: {exc}\n")
