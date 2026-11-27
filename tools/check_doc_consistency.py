# -*- coding: utf-8 -*-
"""Markdown 文档一致性探针（非 CI 闸；按需运行）。"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "manifest.json"
REPORT = ROOT / "qa" / "doc-consistency-report.md"

# 已移除的脚本/路径（2026-11-27）
REMOVED_PATTERNS = [
    r"run_all_smoke\.ps1",
    r"run_godot_smoke\.ps1",
    r"run_save_kill_smoke\.ps1",
    r"validate_data_ci\.py",
    r"validate_config_db\.py",
    r"compare_rules\.py",
    r"run_time_event_sweep\.py",
    r"scripts/qa/",
    r"headless_smoke",
    r"smoke_assertions",
    r"split_smoke_assertions",
]

SKIP_DIRS = {
    "third_party",
    "archive",
    ".git",
    ".cursor",
    "node_modules",
    "agent-tools",
}

# 含已删 runner 字面量但保留作证据，不报错
SKIP_REMOVED_CHECK = {
    "开发计划.md",
    "qa/doc-consistency-report.md",
    "modules/10-validation.md",
    "qa/RF-11.md",
    "sim/README.md",
    "qa/DEV-functional-checklist.md",
    "qa/DEV-day-clock-manual-2026-11-26.md",
    "archive/qa-history/README.md",
    "tools/README.md",
    "qa/整体审计报告-第六轮.md",
    "qa/一致性与逻辑检查-2026-11-27.md",
    "archive/qa-history/CLEANUP-CANDIDATES-2026-11-27.md",
}

ORPHAN_SHELL_RE = re.compile(r"(?<![`\w])壳(?![`\w])")

HEADER_CV_RE = re.compile(
    r"configVersion\s*\*?\*?(\d+)\*?\*?|configVersion:\s*(\d+)|当前\s*`configVersion:\s*(\d+)`",
    re.I,
)


def _manifest_cv() -> int:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return int(data["configVersion"])


def _iter_md() -> list[Path]:
    out: list[Path] = []
    for p in ROOT.rglob("*.md"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        out.append(p)
    return sorted(out)


def _broken_links(text: str, src: Path) -> list[str]:
    errs: list[str] = []
    for m in re.finditer(r"\]\(([^)#]+\.md[^)]*)\)", text):
        target = m.group(1).split("#")[0].strip()
        if target.startswith("http") or target.startswith("/"):
            continue
        resolved = (src.parent / target).resolve()
        if not resolved.is_file():
            alt = (ROOT / target.lstrip("./")).resolve()
            if not alt.is_file():
                errs.append(f"死链 `{target}`")
    return errs


def main() -> int:
    entity_cv = _manifest_cv()
    issues: list[tuple[str, str]] = []

    for path in _iter_md():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")

        if rel not in SKIP_REMOVED_CHECK:
            for pat in REMOVED_PATTERNS:
                if re.search(pat, text, re.I):
                    issues.append((rel, f"引用已删除脚本/路径：/{pat}/"))

        for link_err in _broken_links(text, path):
            issues.append((rel, link_err))

        if "modules/" in rel and ORPHAN_SHELL_RE.search(text) and "「壳」" not in text:
            issues.append((rel, "正文含裸「壳」字（宜用「空壳」或加反引号）"))

        # 权威文档头 configVersion 落后于实体（仅扫前 8 行 + 09 特例行）
        if rel in {
            "README.md",
            "architecture.md",
            "开发计划.md",
            "modules/GODOT_ARCH.md",
            "modules/09-data-platform.md",
            "modules/10-validation.md",
        }:
            head = "\n".join(text.splitlines()[:12])
            nums = []
            for m in HEADER_CV_RE.finditer(head + text[800:1200] if rel == "modules/09-data-platform.md" else head):
                nums.extend(int(x) for x in m.groups() if x)
            if nums and max(nums) < entity_cv:
                issues.append(
                    (rel, f"文档写 configVersion **{max(nums)}**，实体 manifest={entity_cv}")
                )

    lines = [
        "# 文档一致性报告（自动生成）",
        "",
        f"> 实体 `configVersion`：**{entity_cv}**（`data/manifest.json`）",
        f"> 生成：`python tools/check_doc_consistency.py`",
        "",
        f"共 **{len(issues)}** 项。",
        "",
    ]
    if not issues:
        lines.append("未发现死链、已删脚本引用或权威头版本落后。")
    else:
        lines.append("| 文件 | 问题 |")
        lines.append("|---|---|")
        for rel, msg in sorted(issues):
            lines.append(f"| `{rel}` | {msg} |")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"doc consistency: {len(issues)} issue(s) → {REPORT.relative_to(ROOT)}")
    for rel, msg in issues[:30]:
        print(f"  [{rel}] {msg}")
    if len(issues) > 30:
        print(f"  … +{len(issues) - 30} more")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())