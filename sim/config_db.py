# -*- coding: utf-8 -*-
"""In-memory ConfigDb mirror for CI / pre-Godot validation (GODOT_ARCH §2.2)."""
from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union

JsonDict = Dict[str, Any]


class ConfigLoadError(Exception):
    """Raised when manifest entry or require() path is missing."""


@dataclass
class ConfigDb:
    data_root: Path
    tables: Dict[str, JsonDict] = field(default_factory=dict)
    manifests: JsonDict = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)
    _csv_tables: Dict[str, List[JsonDict]] = field(default_factory=dict)

    @classmethod
    def from_repo(cls, repo_root: Optional[Path] = None) -> "ConfigDb":
        root = repo_root or Path(__file__).resolve().parents[1]
        return cls(data_root=root / "data")

    def load_all(self) -> int:
        """Load manifest + every registered file. Returns Error.OK (0) or FAILED (1)."""
        self.errors.clear()
        self.tables.clear()
        self._csv_tables.clear()
        manifest_path = self.data_root / "manifest.json"
        if not manifest_path.is_file():
            self._fail(f"manifest missing: {manifest_path}")
            return 1
        try:
            self.manifests = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            self._fail(f"manifest.json: {exc}")
            return 1

        files = self.manifests.get("files")
        if not isinstance(files, dict) or not files:
            self._fail("manifest.files empty or not an object")
            return 1

        for table_name, rel in files.items():
            path = self.data_root / str(rel).replace("\\", "/")
            if not path.is_file():
                self._fail(f"table {table_name!r}: file not found ({rel})")
                continue
            try:
                if path.suffix.lower() == ".csv":
                    self._load_csv(table_name, path)
                else:
                    payload = json.loads(path.read_text(encoding="utf-8"))
                    if not isinstance(payload, dict):
                        self._fail(f"table {table_name!r}: root must be object")
                        continue
                    self.tables[table_name] = payload
            except json.JSONDecodeError as exc:
                self._fail(f"table {table_name!r} ({rel}): {exc}")
            except OSError as exc:
                self._fail(f"table {table_name!r}: {exc}")

        legacy = self.manifests.get("legacyFiles")
        if isinstance(legacy, dict):
            for table_name, rel in legacy.items():
                path = self.data_root / str(rel).replace("\\", "/")
                if not path.is_file():
                    self._fail(f"legacy table {table_name!r}: file not found ({rel})")
                    continue
                try:
                    payload = json.loads(path.read_text(encoding="utf-8"))
                    if not isinstance(payload, dict):
                        self._fail(f"legacy table {table_name!r}: root must be object")
                        continue
                    self.tables[table_name] = payload
                except json.JSONDecodeError as exc:
                    self._fail(f"legacy table {table_name!r} ({rel}): {exc}")
                except OSError as exc:
                    self._fail(f"legacy table {table_name!r}: {exc}")

        self._cross_validate()
        return 0 if not self.errors else 1

    def _load_csv(self, table_name: str, path: Path) -> None:
        with path.open(encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            if not reader.fieldnames or "key" not in reader.fieldnames:
                self._fail(f"table {table_name!r}: CSV must have 'key' column")
                return
            rows = list(reader)
        self._csv_tables[table_name] = rows
        self.tables[table_name] = {"_csv": True, "rows": rows, "path": str(path.name)}

    def _fail(self, msg: str) -> None:
        self.errors.append(msg)

    def config_version(self) -> int:
        return int(self.manifests.get("configVersion", 0))

    def get_table(self, name: str) -> JsonDict:
        if name not in self.tables:
            raise ConfigLoadError(f"unknown table {name!r}")
        return self.tables[name]

    def has(self, path: str) -> bool:
        try:
            self._resolve(path)
            return True
        except ConfigLoadError:
            return False

    def require(self, path: str) -> Any:
        return self._resolve(path)

    def _resolve(self, path: str) -> Any:
        parts = path.split(".")
        if len(parts) < 2:
            raise ConfigLoadError(f"require path needs table.key form: {path!r}")
        table_name, *rest = parts
        if table_name not in self.tables:
            raise ConfigLoadError(f"missing table for {path!r}")
        cur: Any = self.tables[table_name]
        for key in rest:
            if not isinstance(cur, dict) or key not in cur:
                raise ConfigLoadError(f"missing key: {path!r}")
            cur = cur[key]
        return cur

    def _cross_validate(self) -> None:
        expected_cv = self.config_version()
        if expected_cv <= 0:
            self._fail("manifest.configVersion invalid")
            return

        for name, payload in self.tables.items():
            if payload.get("_csv"):
                continue
            cv = payload.get("configVersion")
            if cv is not None and int(cv) != expected_cv:
                self._fail(
                    f"configVersion mismatch: {name} has {cv}, manifest expects {expected_cv}"
                )

        if self.has("balance.combat.l1Unit") and self.has("combat.l1Unit"):
            b = float(self.require("balance.combat.l1Unit"))
            c = float(self.require("combat.l1Unit"))
            if b != c:
                self._fail(f"balance.combat.l1Unit ({b}) != combat.l1Unit ({c})")

        out = _validate_cross_tables(self)
        for msg in out:
            self._fail(msg)

    def validate_stage(self, stage: str) -> List[str]:
        """Structural checks beyond load_all. Returns new error strings."""
        out: List[str] = []
        stage = stage.lower()
        paths = _required_paths_for_stage(stage)
        for p in paths:
            try:
                self.require(p)
            except ConfigLoadError as exc:
                out.append(str(exc))

        if stage in ("s0", "all"):
            out.extend(_validate_s0(self))
        if stage in ("p1", "s1b", "all"):
            out.extend(_validate_p1(self))
        if stage in ("s2", "all"):
            out.extend(_validate_events(self))

        return out


def _validate_cross_tables(db: ConfigDb) -> List[str]:
    """Doc ↔ data consistency (balance mirrors, start baseline)."""
    errs: List[str] = []
    try:
        start = db.require("balance.start")
        if int(start.get("parts", 0)) != 6 or int(start.get("med", 0)) != 4:
            errs.append(
                "balance.start parts/med must be 6/4 (02-resources.md §10); "
                f"got parts={start.get('parts')} med={start.get('med')}"
            )
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        levels = db.require("upgrades.levels")
        bal_parts = db.require("balance.tech.parts")
        bal_med = db.require("balance.tech.med")
        bal_cat = db.require("balance.tech.catalyst")
        bal_gate = db.require("balance.tech.precisionGate")
        up_gate = db.require("upgrades.precisionGate")
        if list(bal_gate) != list(up_gate):
            errs.append("balance.tech.precisionGate != upgrades.precisionGate")
        for row in levels:
            if not isinstance(row, dict):
                continue
            lv = int(row["lv"]) - 1
            if lv < 0 or lv >= len(bal_parts):
                continue
            if int(row.get("parts", -1)) != int(bal_parts[lv]):
                errs.append(f"balance.tech.parts[lv{lv+1}] != upgrades.levels")
            if int(row.get("medicine", -1)) != int(bal_med[lv]):
                errs.append(f"balance.tech.med[lv{lv+1}] != upgrades.levels")
            if int(row.get("catalyst", -1)) != int(bal_cat[lv]):
                errs.append(f"balance.tech.catalyst[lv{lv+1}] != upgrades.levels")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        int(db.require("stations.guaranteeAfter"))
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        forced = db.require("stations.tutorialForcePointTypes")
        if not isinstance(forced, list) or "supermarket" not in forced or "water_plant" not in forced:
            errs.append("stations.tutorialForcePointTypes must include supermarket + water_plant")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        mods = db.require("point_types.seasonWeightMods")
        if not isinstance(mods, dict) or not mods:
            errs.append("point_types.seasonWeightMods missing or empty")
    except ConfigLoadError as exc:
        if not db.has("point_types.seasonYieldMods"):
            errs.append(str(exc))

    try:
        tr = db.require("balance.train")
        for key, expect in (
            ("abandonPartsCost", (int, float)),
            ("abandonScrapRatio", (int, float)),
            ("abandonFuelCostPct", (int, float)),
            ("abandonAiFuelFillMax", (int, float)),
            ("abandonAiMinCars", int),
        ):
            if key not in tr:
                errs.append(f"balance.train missing {key!r} (03 §4.1)")
            elif not isinstance(tr[key], expect if isinstance(expect, tuple) else (expect,)):
                errs.append(f"balance.train.{key} wrong type")
        ratio = float(tr.get("abandonScrapRatio", 0))
        if not (0 < ratio < 0.7):
            errs.append("balance.train.abandonScrapRatio must be in (0, 0.7) vs workshop 70%")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        hh = db.require("hud_hints.abandonCarriage")
        if hh.get("tipId") != "T11" or hh.get("playerRules") != "R6":
            errs.append("hud_hints.abandonCarriage must tipId=T11 playerRules=R6")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    return errs


def _validate_s0(db: ConfigDb) -> List[str]:
    errs: List[str] = []
    for key in ("regions", "stations", "weather", "point_types", "carriages", "equipment"):
        if key not in db.tables:
            errs.append(f"S0 missing table {key!r}")
    try:
        gates = db.require("balance.tech.precisionGate")
        if not isinstance(gates, list) or len(gates) < 3:
            errs.append("balance.tech.precisionGate must be list len>=3")
    except ConfigLoadError as exc:
        errs.append(str(exc))
    try:
        default_id = db.require("difficulty.defaultId")
        tiers = db.require("difficulty.tiers")
        if default_id not in tiers:
            errs.append(f"difficulty.defaultId {default_id!r} not in tiers")
    except ConfigLoadError as exc:
        errs.append(str(exc))
    return errs


def _validate_p1(db: ConfigDb) -> List[str]:
    errs: List[str] = []
    try:
        abilities = db.require("abilities.abilities")
        if not isinstance(abilities, list) or len(abilities) != 11:
            errs.append(f"abilities.abilities expected 11 entries, got {len(abilities) if isinstance(abilities, list) else 'non-list'}")
        ids = {a.get("id") for a in abilities if isinstance(a, dict)}
        expected = {
            "sense", "barrier", "heal", "telekinesis", "shockwave",
            "armor_break", "berserk", "carapace", "rally", "silence", "blink_aid",
        }
        missing = expected - ids
        if missing:
            errs.append(f"abilities missing ids: {sorted(missing)}")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        targets = db.require("combat_targets.targets")
        if not isinstance(targets, list) or len(targets) < 1:
            errs.append("combat_targets.targets must be non-empty list")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        objectives = db.require("combat_objectives.objectives")
        if len(objectives) != 16:
            errs.append(f"combat_objectives expected 16, got {len(objectives)}")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    try:
        party = db.require("archetypes.startPartyTemplate.members")
        if len(party) != 4:
            errs.append(f"archetypes.startPartyTemplate must have 4 members, got {len(party)}")
        jobs = [m.get("job") for m in party if isinstance(m, dict)]
        if jobs.count("none") != 4:
            errs.append("startPartyTemplate: all 4 members must have job=none (player assigns)")
    except ConfigLoadError as exc:
        errs.append(str(exc))

    for csv_key in (
        "localization_ui",
        "localization_combat",
        "localization_abilities",
        "localization_events_general",
        "localization_events_season",
        "localization_events_year",
    ):
        if csv_key not in db.tables:
            errs.append(f"missing localization table {csv_key!r}")
            continue
        rows = db.tables[csv_key].get("rows", [])
        if not rows:
            errs.append(f"{csv_key}: empty CSV")
    return errs


_EVENT_OP_WHITELIST = frozenset(
    {
        "grant_item",
        "grant_blueprint",
        "remove_item",
        "mood_delta",
        "grant_influence",
        "clear_influence",
        "spawn_threat",
        "weight_mod",
        "flag_set",
        "recruit_roll",
        "loot_halve",
    }
)


def _iter_event_card_ops(card: dict) -> List[str]:
    ops: List[str] = []
    for opt in card.get("options") or []:
        if not isinstance(opt, dict):
            continue
        imm = opt.get("immediate")
        if isinstance(imm, dict) and imm.get("op"):
            ops.append(str(imm["op"]))
        if opt.get("op"):
            ops.append(str(opt["op"]))
    return ops


def _validate_events(db: ConfigDb) -> List[str]:
    errs: List[str] = []
    try:
        from sim.event_loader import load_event_catalog, load_event_index
    except ImportError:
        from event_loader import load_event_catalog, load_event_index

    try:
        index = load_event_index()
        target = int(index.get("targetTotal", 0))
        catalog = load_event_catalog()
        if len(catalog) != target:
            errs.append(f"events: catalog {len(catalog)} != targetTotal {target}")
        if index.get("configVersion") != db.config_version():
            errs.append("events/_index configVersion != manifest")
        want_cv = db.config_version()
        for eid, card in catalog.items():
            if not isinstance(card, dict):
                errs.append(f"events: {eid} not a dict")
                continue
            if int(card.get("configVersion", 0)) != want_cv:
                errs.append(f"events: {eid} configVersion != manifest")
            for req_key in ("weightEventId", "weight", "yieldScale"):
                if req_key not in card:
                    errs.append(f"events: {eid} missing {req_key}")
            opts = card.get("options")
            if not isinstance(opts, list) or len(opts) < 2:
                errs.append(f"events: {eid} options len < 2")
            for op in _iter_event_card_ops(card):
                if op not in _EVENT_OP_WHITELIST:
                    errs.append(f"events: {eid} unknown op {op!r}")
    except Exception as exc:  # noqa: BLE001 — validator aggregates
        errs.append(f"events: {exc}")
    return errs


def _required_paths_for_stage(stage: str) -> Sequence[str]:
    s0 = [
        "balance.time.secondsPerDay",
        "balance.time.daysPerSeason",
        "balance.time.driveHoursPerDayCap",
        "balance.start.food",
        "balance.start.water",
        "balance.start.fuel",
        "balance.start.parts",
        "balance.start.med",
        "balance.start.carriages",
        "balance.start.precision",
        "balance.start.seed",
        "balance.fuel.base",
        "balance.greenhouse.heatingFuelPerCarDay",
        "balance.greenhouse.heatingMult",
        "balance.workshop.precisionStart",
        "stations.guaranteeAfter",
        "stations.segmentLengthMin",
        "stations.segmentLengthMax",
        "weather.weathers",
        "regions.regions",
        "point_types.types",
        "carriages.templates",
        "equipment.equipment",
        "climate_influences.presets",
        "upgrades.lines",
        "hud_hints.fuelFill",
    ]
    p1 = [
        "combat.l1Unit",
        "combat.l1Success.min",
        "combat.searchEncounter",
        "gear.types.ranged.rangedBonus",
        "gear.types.melee.meleeBonus",
        "gear.types.defense.defBonus",
        "disease.streakThreshold",
        "disease.treatment.defaultDays",
        "items.potions",
        "archetypes.archetypes",
        "archetypes.startPartyTemplate.members",
        "combat_trauma.tags",
        "migrations_manifest.saveSchemaCurrent",
        "balance.haul.hoursPerTask",
        "balance.search.hoursPerTask",
        "balance.greenhouse.fullOutputPerDay",
        "balance.water.basicOutputPerDay",
        "balance.train.abandonScrapRatio",
        "balance.inventory.base.food",
        "balance.fuelTank.baseAmount",
        "balance.travel.corridorMult",
        "balance.eventDraw.scenarioEventRate",
        "combat.threatTemplateAliases",
    ]
    if stage == "s0":
        return s0
    if stage in ("p1", "s1b"):
        return s0 + p1
    if stage == "s2":
        return s0 + p1
    return s0 + p1


def run_validation(
    *,
    repo_root: Optional[Path] = None,
    stage: str = "s1b",
) -> Tuple[int, List[str]]:
    """Load all tables and run stage checks. Exit code 0 = pass."""
    db = ConfigDb.from_repo(repo_root)
    code = db.load_all()
    messages = list(db.errors)
    if code == 0:
        messages.extend(db.validate_stage(stage))
    if messages:
        return 1, messages
    return 0, []