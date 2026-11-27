# -*- coding: utf-8 -*-
"""CSV 五语列、{n} 占位符个数、译文长度异常（相对 zh）。"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALE_DIR = ROOT / "data" / "localization"
LANGS = ("en", "zh", "de", "ru", "es")
PLACEHOLDER = re.compile(r"\{(\d+)\}")


def _placeholder_count(text: str) -> int:
    nums = [int(m.group(1)) for m in PLACEHOLDER.finditer(text)]
    if not nums:
        return 0
    return max(nums) + 1


def main() -> int:
    errs: list[str] = []
    for path in sorted(LOCALE_DIR.glob("*.csv")):
        with path.open(encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            fields = reader.fieldnames or []
            for lang in LANGS:
                if lang not in fields:
                    errs.append(f"{path.name}: missing column {lang}")
            for row in reader:
                key = (row.get("key") or "").strip()
                if not key or key == "key":
                    continue
                ph_counts = {}
                lengths = {}
                for lang in LANGS:
                    val = (row.get(lang) or "").strip()
                    ph_counts[lang] = _placeholder_count(val)
                    lengths[lang] = len(val)
                base_ph = ph_counts.get("zh", 0)
                for lang in LANGS:
                    if ph_counts.get(lang, 0) != base_ph:
                        errs.append(f"{path.name} {key}: placeholder mismatch zh={base_ph} {lang}={ph_counts[lang]}")
                zh_len = lengths.get("zh", 0)
                if zh_len >= 10:
                    for lang in LANGS:
                        if lang == "zh":
                            continue
                        if lengths.get(lang, 0) > zh_len * 5:
                            errs.append(
                                f"{path.name} {key}: {lang} len {lengths[lang]} >> zh {zh_len} (×5)"
                            )

    print(f"audit_locale_placeholders: csv_files={len(list(LOCALE_DIR.glob('*.csv')))}")
    if errs:
        print("audit_locale_placeholders: FAIL")
        for e in errs[:30]:
            print(" ", e)
        if len(errs) > 30:
            print(f"  … +{len(errs) - 30} more")
        return 1
    print("audit_locale_placeholders: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())