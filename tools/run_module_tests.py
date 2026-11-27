# -*- coding: utf-8 -*-
"""按设计模块 / 客户端分层编排自动化回归（无需 Godot 亦可跑大部分）。"""
from __future__ import annotations

import argparse
import ast
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))


@dataclass
class StepResult:
    name: str
    ok: bool
    lines: list[str] = field(default_factory=list)
    skipped: bool = False


@dataclass
class ModuleResult:
    module_id: str
    title: str
    steps: list[StepResult] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(s.ok or s.skipped for s in self.steps) and any(
            not s.skipped for s in self.steps
        )

    def failed_steps(self) -> list[StepResult]:
        return [s for s in self.steps if not s.ok and not s.skipped]


def _run_script(rel: str, extra: list[str] | None = None) -> StepResult:
    path = ROOT / rel
    cmd = [sys.executable, str(path), *(extra or [])]
    proc = subprocess.run(
        cmd, cwd=str(ROOT), capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )
    tail = ((proc.stdout or "") + (proc.stderr or "")).strip().splitlines()
    summary = tail[-1] if tail else ""
    ok = proc.returncode == 0
    lines = tail[-8:] if tail else [f"exit {proc.returncode}"]
    return StepResult(path.name, ok, [summary or "; ".join(lines[-3:])])


def _run_ps1(rel: str) -> StepResult:
    path = ROOT / rel
    proc = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(path)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    tail = ((proc.stdout or "") + (proc.stderr or "")).strip().splitlines()
    ok = proc.returncode == 0
    last = tail[-1] if tail else f"exit {proc.returncode}"
    return StepResult(path.name, ok, [last])


def _godot_bin() -> Path | None:
    env = os.environ.get("GODOT_BIN")
    if env and Path(env).is_file():
        return Path(env)
    for p in (
        Path(r"D:\godot\Godot_v4.7.2-stable_win64_console.exe"),
        Path(r"D:\godot\Godot_v4.7.2-stable_win64.exe"),
    ):
        if p.is_file():
            return p
    return None


def step_static_syntax() -> StepResult:
    bad_py: list[str] = []
    for base in (ROOT / "sim", ROOT / "tools"):
        for path in base.rglob("*.py"):
            if path.name.startswith("."):
                continue
            try:
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            except SyntaxError as exc:
                bad_py.append(f"{path.relative_to(ROOT)}: {exc}")
    bad_json: list[str] = []
    for base in (ROOT / "data", ROOT / "client" / "data"):
        if not base.is_dir():
            continue
        for path in base.rglob("*.json"):
            try:
                json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                bad_json.append(f"{path.relative_to(ROOT)}: {exc}")
    if bad_py or bad_json:
        return StepResult(
            "PY_JSON_PARSE",
            False,
            [f"py_bad={len(bad_py)} json_bad={len(bad_json)}"] + bad_py[:5] + bad_json[:5],
        )
    py_n = sum(1 for _ in (ROOT / "sim").rglob("*.py")) + sum(
        1 for _ in (ROOT / "tools").rglob("*.py")
    )
    json_n = sum(1 for _ in (ROOT / "data").rglob("*.json"))
    if (ROOT / "client" / "data").is_dir():
        json_n += sum(1 for _ in (ROOT / "client" / "data").rglob("*.json"))
    return StepResult("PY_JSON_PARSE", True, [f"files py={py_n} json={json_n} bad=0"])


def step_inventory_cap_alignment() -> StepResult:
    """02 §6：货舱 size=3 时 parts=30、medicine=20（lifeMult=1）与 sim 一致。"""
    from config_db import ConfigDb  # noqa: E402
    from engine import RunState, starter_train  # noqa: E402

    db = ConfigDb.from_repo(ROOT)
    if db.load_all() != 0:
        return StepResult("inventory_cap", False, db.errors[:3])
    parts_t = float(db.require("balance.inventory.cargoPerSize.partsTenth"))
    med_t = float(db.require("balance.inventory.cargoPerSize.medicineChemTenth"))
    base_p = float(db.require("balance.inventory.base.parts"))
    base_m = float(db.require("balance.inventory.base.medicine"))
    cargo = 3.0
    parts_cap = base_p + round(cargo * parts_t / 3.0)
    med_cap = base_m + round(cargo * med_t / 3.0)
    st = RunState()
    st.cars = list(starter_train())
    sim_parts = st.stock_cap_parts()
    sim_med = st.stock_cap_med()
    if abs(parts_cap - sim_parts) > 0.01 or abs(med_cap - sim_med) > 0.01:
        return StepResult(
            "inventory_cap",
            False,
            [
                f"expected parts={parts_cap} med={med_cap} got sim parts={sim_parts} med={sim_med}"
            ],
        )
    return StepResult("inventory_cap", True, [f"parts={int(parts_cap)} medicine={int(med_cap)}"])


def step_godot_save_migration() -> StepResult:
    exe = _godot_bin()
    if exe is None:
        return StepResult("SaveMigrationProbe", True, ["SKIP (set GODOT_BIN)"], skipped=True)
    script = ROOT / "client" / "scripts" / "debug" / "save_migration_probe_runner.gd"
    proc = subprocess.run(
        [str(exe), "--headless", "--path", str(ROOT / "client"), "--script", str(script)],
        capture_output=True,
        text=True,
        timeout=180,
        cwd=str(ROOT / "client"),
    )
    if proc.returncode != 0:
        return StepResult("SaveMigrationProbe", False, [(proc.stdout + proc.stderr)[-800:]])
    out = proc.stdout.strip().splitlines()
    return StepResult("SaveMigrationProbe", True, [out[-1] if out else "ok"])


def step_godot_hc_config() -> StepResult:
    exe = _godot_bin()
    if exe is None:
        return StepResult("HcConfigProbe", True, ["SKIP (set GODOT_BIN)"], skipped=True)
    script = ROOT / "client" / "scripts" / "debug" / "hc_config_probe_runner.gd"
    proc = subprocess.run(
        [str(exe), "--headless", "--path", str(ROOT / "client"), "--script", str(script)],
        capture_output=True,
        text=True,
        timeout=180,
        cwd=str(ROOT / "client"),
    )
    if proc.returncode != 0:
        return StepResult("HcConfigProbe", False, [(proc.stdout + proc.stderr)[-600:]])
    out = proc.stdout.strip().splitlines()
    return StepResult("HcConfigProbe", True, [out[-1] if out else "ok"])


def step_godot_a6_only() -> StepResult:
    exe = _godot_bin()
    if exe is None:
        return StepResult("A6Batch0Probe", True, ["SKIP (set GODOT_BIN)"], skipped=True)
    script = ROOT / "client" / "scripts" / "debug" / "a6_probe_runner.gd"
    proc = subprocess.run(
        [str(exe), "--headless", "--path", str(ROOT / "client"), "--script", str(script)],
        capture_output=True,
        text=True,
        timeout=180,
        cwd=str(ROOT / "client"),
    )
    if proc.returncode != 0:
        return StepResult("A6Batch0Probe", False, [(proc.stdout + proc.stderr)[-600:]])
    out = proc.stdout.strip().splitlines()
    return StepResult("A6Batch0Probe", True, [out[-1] if out else "ok"])


def step_zero_a_smoke() -> StepResult:
    return _run_script("tools/run_zero_a.py", ["--runs", "250"])


def step_save_migration_py() -> StepResult:
    return _run_script("tools/probe_save_migration.py")


def step_probe_h3_m4r() -> StepResult:
    import importlib.util

    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    spec = importlib.util.spec_from_file_location(
        "probe_a6_signoff", ROOT / "tools" / "probe_a6_signoff.py"
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    ok_h3, lines_h3 = mod.check_h3()
    ok_m4, lines_m4 = mod.check_m4r()
    ok = ok_h3 and ok_m4
    lines = [ln for ln in lines_h3 + lines_m4 if ln.startswith(("OK", "FAIL"))]
    return StepResult("sim_probe_h3_m4r", ok, lines or ["FAIL"])


# module_id -> (title, list of step factories)
MODULES: dict[str, tuple[str, list[Callable[[], StepResult]]]] = {
    "static": ("m00 · 静态语法", [step_static_syntax]),
    "data": (
        "m09 · 数据平台 / 配置",
        [
            lambda: _run_script("tools/smoke_config.py"),
            lambda: _run_script("tools/probe_config_paths.py"),
            lambda: _run_script("tools/probe_orphan_data.py"),
            step_inventory_cap_alignment,
            step_zero_a_smoke,
            step_save_migration_py,
        ],
    ),
    "events": (
        "m06 · 事件 / event_ops",
        [
            lambda: _run_script("tools/smoke_config.py"),
            lambda: _run_script("tools/probe_event_weight_mc.py"),
        ],
    ),
    "incidents": (
        "m06 · Incident 导演",
        [lambda: _run_script("tools/stress_sweep.py")],
    ),
    "sim": (
        "m01–03 · 模拟器日环 / 进站",
        [
            step_probe_h3_m4r,
            lambda: _run_script("tools/probe_long_run_stability.py"),
        ],
    ),
    "signoff": (
        "A6 全量签字探针",
        [lambda: _run_script("tools/probe_a6_signoff.py")],
    ),
    "locale": (
        "m08 · 本地化",
        [
            lambda: _run_script("tools/audit_locale_keys.py"),
            lambda: _run_script("tools/audit_locale_placeholders.py"),
            lambda: _run_script("tools/probe_locale_registration.py"),
        ],
    ),
    "docs": (
        "文档一致性闸",
        [lambda: _run_script("tools/check_doc_consistency.py")],
    ),
    "hardcode": (
        "客户端硬编码启发式",
        [lambda: _run_script("tools/scan_hardcode_gd.py")],
    ),
    "client": (
        "Godot 客户端（编译 + 域探针）",
        [
            lambda: (
                _run_ps1("tools/godot_compile_check.ps1")
                if _godot_bin()
                else StepResult("godot_compile_check", True, ["SKIP (set GODOT_BIN)"], skipped=True)
            ),
            step_godot_hc_config,
            step_godot_save_migration,
            step_godot_a6_only,
        ],
    ),
    "gameplay": (
        "client/gameplay · 区域/堆/搬运",
        [step_godot_a6_only],
    ),
}


def run_module(module_id: str) -> ModuleResult:
    title, factories = MODULES[module_id]
    mod = ModuleResult(module_id, title)
    seen: set[str] = set()
    for fn in factories:
        step = fn()
        key = step.name
        if key in seen and step.name.endswith(".py"):
            continue
        seen.add(key)
        mod.steps.append(step)
    return mod


def run_all(module_ids: list[str]) -> list[ModuleResult]:
    return [run_module(mid) for mid in module_ids]


def default_suite() -> list[str]:
    return [
        "static",
        "data",
        "incidents",
        "sim",
        "signoff",
        "locale",
        "docs",
        "hardcode",
        "client",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="按模块运行自动化回归")
    parser.add_argument(
        "--module",
        "-m",
        action="append",
        dest="modules",
        help=f"模块 id：{', '.join(MODULES)}",
    )
    parser.add_argument("--list", action="store_true", help="列出模块")
    args = parser.parse_args()
    if args.list:
        for mid, (title, _) in MODULES.items():
            print(f"{mid:12} {title}")
        return 0
    ids = args.modules or default_suite()
    for mid in ids:
        if mid not in MODULES:
            print(f"unknown module: {mid}", file=sys.stderr)
            return 2
    results = run_all(ids)
    fail = False
    print("module_tests")
    print("=" * 60)
    for mod in results:
        status = "OK" if mod.ok else "FAIL"
        if not any(not s.skipped for s in mod.steps):
            status = "SKIP"
        print(f"[{status}] {mod.module_id} — {mod.title}")
        for step in mod.steps:
            tag = "skip" if step.skipped else ("ok" if step.ok else "FAIL")
            print(f"    {tag:4} {step.name}")
            for ln in step.lines[:4]:
                print(f"         {ln}")
        if mod.failed_steps():
            fail = True
        print()
    print("run_module_tests:", "OK" if not fail else "FAIL")
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())