# Sync all data/*.json configVersion to manifest.configVersion (data + client/data).
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
manifest = json.loads((ROOT / "data" / "manifest.json").read_text(encoding="utf-8"))
want = int(manifest.get("configVersion", 0))
pattern = re.compile(r'"configVersion":\s*\d+')
changed = 0
for base in (ROOT / "data", ROOT / "client" / "data"):
    if not base.is_dir():
        continue
    for p in base.rglob("*.json"):
        text = p.read_text(encoding="utf-8")
        if '"configVersion"' not in text:
            continue
        new = pattern.sub(f'"configVersion": {want}', text, count=1)
        if new != text:
            p.write_text(new, encoding="utf-8")
            changed += 1
print(f"sync_config_version: manifest={want}, files_updated={changed}")