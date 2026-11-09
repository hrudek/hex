#!/usr/bin/env python3
"""Explicit local commands; never contacts a service or runs a speech/AI model."""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from archive import Invalid, read_export
from report import human, make_report
from store import Store


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store", type=Path, required=True, help="Private directory outside every Git checkout")
    commands = parser.add_subparsers(dest="command", required=True)
    importer = commands.add_parser("import", help="Validate and import one explicit JSON export")
    importer.add_argument("export", type=Path)
    importer.add_argument("--json", action="store_true")
    reporter = commands.add_parser("report", help="Observational summary; no ranking or inference")
    reporter.add_argument("--json", action="store_true")
    reporter.add_argument("--show-text", action="store_true", help="Explicitly include private text and vocabulary")
    args = parser.parse_args(argv)
    try:
        if args.command == "import":
            export = read_export(args.export)  # Validate the whole input before any store mutation.
            with Store(args.store, create=True) as store:
                result = store.import_export(export)
            if args.json:
                print(json.dumps(result, sort_keys=True))
            else:
                print("Imported: " + ", ".join(f"{key}={value}" for key, value in result.items() if key != "warnings"))
                for warning in result["warnings"]:
                    print("Warning: " + warning)
        else:
            with Store(args.store) as store:
                result = make_report(store, show_text=args.show_text)
            print(json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2) if args.json else human(result))
        return 0
    except Invalid as error:
        print("Error: " + str(error), file=sys.stderr)
    except (OSError, sqlite3.Error, ValueError, OverflowError, RecursionError):
        # Do not echo exception contents: a JSON value, SQLite data or a filename may be private.
        print("Error: local input/store operation failed; existing committed data was not replaced by an invalid import",
              file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
