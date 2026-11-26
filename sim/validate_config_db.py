# -*- coding: utf-8 -*-
"""ConfigDb load + require-path smoke (GODOT_ARCH S0.2 / §2.2)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from sim.config_db import ConfigDb, run_validation
else:
    from sim.config_db import ConfigDb, run_validation


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Load data/manifest.json tables and verify require() paths.",
    )
    parser.add_argument(
        "--stage",
        choices=["s0", "p1", "s1b", "s2", "all"],
        default="s1b",
        help="s0=节奏/进站; s1b=s0+p1(默认); s2=+120事件; all=s2",
    )
    parser.add_argument(
        "--probe",
        metavar="PATH",
        action="append",
        default=[],
        help="Extra dot path to require() after load (e.g. balance.start.fuel)",
    )
    parser.add_argument(
        "--list-tables",
        action="store_true",
        help="Print loaded table names and exit 0 on successful load",
    )
    args = parser.parse_args()

    db = ConfigDb.from_repo()
    code = db.load_all()
    if code != 0:
        _print_errors(db.errors)
        return 1

    stage = "s2" if args.stage == "all" else args.stage
    extra = db.validate_stage(stage)
    for path in args.probe:
        try:
            val = db.require(path)
            print(f"probe OK {path} = {val!r}")
        except Exception as exc:  # noqa: BLE001
            extra.append(f"probe {path}: {exc}")

    if args.list_tables:
        print(f"configVersion={db.config_version()} tables={len(db.tables)}")
        for name in sorted(db.tables):
            print(f"  - {name}")
        if extra:
            _print_errors(extra)
            return 1
        print("ConfigDb load: OK")
        return 0

    if extra:
        _print_errors(extra)
        return 1

    print(
        f"ConfigDb load: OK (configVersion={db.config_version()}, "
        f"tables={len(db.tables)}, stage={args.stage})"
    )
    return 0


def _print_errors(errors: list) -> None:
    print("ConfigDb load: FAILED", file=sys.stderr)
    for msg in errors:
        print(f"  • {msg}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())