# -*- coding: utf-8 -*-
"""Scan client GD for LocaleDb keys vs data/localization/*.csv (DEV-D 裸键)."""
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "client" / "scripts"
LOCALE_DIR = ROOT / "data" / "localization"
QA_OUT = ROOT / "qa" / "locale-key-audit.md"

TR_KEY = re.compile(r'LocaleDb\.(?:tr_key|trf?)\(\s*"([^"]+)"')
TR_CODE = re.compile(r'LocaleDb\.tr_code\(\s*"([^"]+)"\s*,\s*([^,\)]+)')

KNOWN_TR_CODE_PREFIXES: dict[str, list[str]] = {
	"season": ["spring", "summer", "autumn", "winter"],
	"drive": ["stop", "forward", "reverse"],
	"job": [
		"grower", "crafter", "purifier", "pharmacist", "radar_op",
		"engineer", "guard", "labor", "none",
	],
	"spec": [
		"scavenge", "repair", "medicine", "pharmacy", "farming", "haul", "combat_drill",
	],
	"carriage": ["power", "living", "cargo", "greenhouse", "workshop", "water", "medical"],
	"station.condition": ["intact", "damaged", "wreck"],
	"station.miss": ["no_pool", "empty_roll", "no_offer"],
	"combat.tactic": ["assault", "negotiate", "bypass", "horn", "evacuate"],
	"combat.err": [],
	"search.err": [],
	"tech.err": [],
	"train.abandon": [],
	"region.pick": [],
}


def load_csv_keys() -> set[str]:
	keys: set[str] = set()
	for path in sorted(LOCALE_DIR.glob("*.csv")):
		with path.open(encoding="utf-8", newline="") as fh:
			for row in csv.reader(fh):
				if row and row[0].strip() and row[0] != "key":
					keys.add(row[0].strip())
	return keys


def scan_gd() -> tuple[set[str], list[tuple[str, str, int]]]:
	static_keys: set[str] = set()
	dynamic: list[tuple[str, str, int]] = []  # file, prefix, line
	for gd in sorted(SCRIPTS.rglob("*.gd")):
		text = gd.read_text(encoding="utf-8")
		for i, line in enumerate(text.splitlines(), start=1):
			for m in TR_KEY.finditer(line):
				static_keys.add(m.group(1))
			for m in TR_CODE.finditer(line):
				prefix = m.group(1)
				code_expr = m.group(2).strip()
				if code_expr.startswith('"') and code_expr.endswith('"'):
					static_keys.add(f"{prefix}.{code_expr[1:-1]}")
				else:
					dynamic.append((str(gd.relative_to(ROOT)), prefix, i))
	return static_keys, dynamic


def resolve_dynamic(prefix: str, csv_keys: set[str]) -> list[str]:
	samples = KNOWN_TR_CODE_PREFIXES.get(prefix)
	if samples:
		return [f"{prefix}.{s}" for s in samples]
	return sorted(k for k in csv_keys if k.startswith(prefix + "."))


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--write", action="store_true", help="Write qa/locale-key-audit.md")
	args = parser.parse_args()

	csv_keys = load_csv_keys()
	static_keys, dynamic = scan_gd()

	missing_exact = sorted(k for k in static_keys if k not in csv_keys)
	prefix_gaps: list[str] = []
	for _file, prefix, line in dynamic:
		candidates = resolve_dynamic(prefix, csv_keys)
		missing = [c for c in candidates if c not in csv_keys]
		if missing:
			prefix_gaps.append(f"{_file}:{line} tr_code('{prefix}', …) — sample missing: {', '.join(missing[:5])}")

	lines = [
		"# Locale 键审计（自动生成）",
		"",
		f"- CSV 键总数：`{len(csv_keys)}`",
		f"- GD 静态 `tr_key`/`trf`/`tr` 引用：`{len(static_keys)}`",
		f"- 动态 `tr_code` 调用点：`{len(dynamic)}`",
		"",
		"## 静态键缺行（需补 CSV 或改代码）",
		"",
	]
	if missing_exact:
		for k in missing_exact:
			lines.append(f"- `{k}`")
	else:
		lines.append("- （无）")
	lines += ["", "## 动态 tr_code 抽样缺键", ""]
	if prefix_gaps:
		for g in sorted(set(prefix_gaps)):
			lines.append(f"- {g}")
	else:
		lines.append("- （抽样均命中，或未登记 KNOWN_TR_CODE_PREFIXES）")

	report = "\n".join(lines) + "\n"
	print(report)
	if missing_exact:
		print(f"\nFAIL: {len(missing_exact)} static key(s) missing from CSV", file=sys.stderr)
	else:
		print("\nOK: all static LocaleDb keys exist in CSV")

	if args.write:
		QA_OUT.parent.mkdir(parents=True, exist_ok=True)
		QA_OUT.write_text(report, encoding="utf-8")
		print(f"Wrote {QA_OUT}")

	return 1 if missing_exact else 0


if __name__ == "__main__":
	raise SystemExit(main())