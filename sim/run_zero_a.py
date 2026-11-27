# -*- coding: utf-8 -*-
"""兼容入口：`python sim/run_zero_a.py` → `tools/run_zero_a.py`。"""
from __future__ import annotations

import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
runpy.run_path(str(ROOT / "tools" / "run_zero_a.py"), run_name="__main__")