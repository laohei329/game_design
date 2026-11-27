# -*- coding: utf-8 -*-
"""CI: data/ vs client/data/ 同步 + 战斗威胁模板 id 校验。"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
CLIENT_DATA = ROOT / "client" / "data"
KNOWN_THREAT_ALIASES = frozenset({"horde_small", "horde_medium", "rotter"})


def _load_manifest(root: Path) -> dict:
    path = root / "manifest.json"
    return json.loads(path.read_text(encoding="utf-8"))


def check_mirror_sync() -> list[str]:
    errs: list[str] = []
    man = _load_manifest(DATA)
    files: dict = man.get("files") or {}
    for _name, rel in sorted(files.items()):
        rel = str(rel).replace("\\", "/")
        if rel.endswith(".csv"):
            continue
        p1 = DATA / rel
        p2 = CLIENT_DATA / rel
        if not p1.is_file():
            errs.append(f"missing repo data/{rel}")
            continue
        if not p2.is_file():
            errs.append(f"missing client/data/{rel}")
            continue
        if p1.read_bytes() != p2.read_bytes():
            errs.append(f"bytes differ: {rel}")
    # 事件 JSON 不在 manifest 逐条列出
    ev1 = DATA / "events"
    ev2 = CLIENT_DATA / "events"
    if ev1.is_dir():
        for p in ev1.rglob("*.json"):
            rel = p.relative_to(DATA).as_posix()
            q = CLIENT_DATA / rel
            if not q.is_file():
                errs.append(f"missing client/data/{rel}")
            elif p.read_bytes() != q.read_bytes():
                errs.append(f"bytes differ: {rel}")
    if ev2.is_dir() and ev1.is_dir():
        for p in ev2.rglob("*.json"):
            rel = p.relative_to(CLIENT_DATA).as_posix()
            if not (DATA / rel).is_file():
                errs.append(f"orphan client/data/{rel}")
    cm = _load_manifest(CLIENT_DATA)
    if cm.get("configVersion") != man.get("configVersion"):
        errs.append(
            f"manifest configVersion data={man.get('configVersion')} "
            f"client={cm.get('configVersion')}"
        )
    return errs


def _target_ids(root: Path) -> set[str]:
    raw = json.loads((root / "combat-targets.json").read_text(encoding="utf-8"))
    return {str(t["id"]) for t in raw.get("targets", []) if isinstance(t, dict) and t.get("id")}


def _aliases(root: Path) -> dict[str, str]:
    combat = json.loads((root / "combat.json").read_text(encoding="utf-8"))
    aliases = combat.get("threatTemplateAliases") or {}
    if not isinstance(aliases, dict):
        return {}
    return {str(k): str(v) for k, v in aliases.items()}


def _resolve(tpl: str, aliases: dict[str, str]) -> str:
    return aliases.get(tpl, tpl)


def check_threat_templates() -> list[str]:
    errs: list[str] = []
    targets = _target_ids(DATA)
    aliases = _aliases(DATA)
    combat = json.loads((DATA / "combat.json").read_text(encoding="utf-8"))
    enc = combat.get("searchEncounter") or {}
    by_type = enc.get("templateByPointType") or {}
    for ptype, tpl in by_type.items():
        resolved = _resolve(str(tpl), aliases)
        if resolved not in targets:
            errs.append(f"searchEncounter.{ptype}={tpl!r} → {resolved!r} not in combat-targets")
    # 事件卡 spawn_threat
    for p in (DATA / "events").rglob("*.json"):
        try:
            card = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            errs.append(f"bad json {p.relative_to(DATA)}")
            continue
        for opt in card.get("options") or []:
            if not isinstance(opt, dict):
                continue
            blocks: list[dict] = []
            imm = opt.get("immediate")
            if isinstance(imm, dict) and imm.get("op"):
                blocks.append(imm)
            if opt.get("op"):
                blocks.append(opt)
            for block in blocks:
                if block.get("op") != "spawn_threat":
                    continue
                args = block.get("args")
                if not isinstance(args, dict):
                    continue
                tpl = args.get("threatTemplateId")
                if not tpl:
                    continue
                resolved = _resolve(str(tpl), aliases)
                if resolved not in targets:
                    rel = p.relative_to(DATA)
                    errs.append(f"{rel}: threat {tpl!r} → {resolved!r} missing")
    return errs


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate data mirror + combat templates.")
    args = parser.parse_args()
    _ = args
    all_errs = check_mirror_sync() + check_threat_templates()
    if all_errs:
        print("validate_data_ci: FAILED", file=sys.stderr)
        for msg in all_errs:
            print(f"  • {msg}", file=sys.stderr)
        return 1
    print("validate_data_ci: OK (mirror + threat templates)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())