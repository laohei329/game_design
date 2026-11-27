#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""已弃用：本轮曾临时重建最小 runner，现由 tools/run_zero_a.py 取代。

请直接运行：
    python tools/run_zero_a.py --runs 250 --strict
"""
from __future__ import annotations

import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
print("DEPRECATED: use tools/run_zero_a.py --runs 250 --strict", file=sys.stderr)
runpy.run_path(str(ROOT / "tools" / "run_zero_a.py"), run_name="__main__")
