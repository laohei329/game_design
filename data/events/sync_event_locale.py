# -*- coding: utf-8 -*-
"""Event cards ↔ localization CSV (08 五语). Buckets: general · season · year."""
from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
LOC_DIR = Path(__file__).resolve().parents[1] / "localization"
LOCALE_COLS = ("en", "zh", "de", "ru", "es")

# 六类钩子 × 五语（标题 + 正文基线）；正文细节仍以 CSV 每卡行为准
HOOK_I18N: Dict[str, Dict[str, Dict[str, str]]] = {
    "路边信号": {
        "title": {
            "en": "Roadside Signal",
            "zh": "路边信号",
            "de": "Signal am Gleis",
            "ru": "Сигнал у путей",
            "es": "Señal junto a la vía",
        },
        "body_base": {
            "en": "Someone flashes a hand lamp beside the buckled rails, then freezes when the headlight catches them.",
            "zh": "有人在废轨旁举起手电。",
            "de": "Jemand blinkt mit einer Handlampe neben verbogenen Schienen und erstarrt im Scheinwerferlicht.",
            "ru": "Кто-то машет ручным фонарём у погнутых рельсов и замирает в луче прожектора.",
            "es": "Alguien enciende una linterna junto a los raíles torcidos y se queda quieto bajo el faro.",
        },
    },
    "余烬营地": {
        "title": {
            "en": "Ember Camp",
            "zh": "余烬营地",
            "de": "Glutlager",
            "ru": "Лагерь углей",
            "es": "Campamento de brasas",
        },
        "body_base": {
            "en": "A fire still smolders ahead; you cannot tell if anyone is left watching it.",
            "zh": "远处有未熄尽的火，不确定还有没有幸存者。",
            "de": "Vorne glimmt noch ein Feuer; unklar, ob noch jemand Wache hält.",
            "ru": "Впереди тлеет костёр; неясно, остался ли кто-то нести вахту.",
            "es": "Un fuego aún humea adelante; no se sabe si alguien lo vigila.",
        },
    },
    "铁轨异响": {
        "title": {
            "en": "Rail Joint Scream",
            "zh": "铁轨异响",
            "de": "Schrei der Schiene",
            "ru": "Визг стыка",
            "es": "Chirriar del raíl",
        },
        "body_base": {
            "en": "The wheels hammer a bent fishplate—something heavy passed here recently.",
            "zh": "车轮压过变形的接头，像是刚发生过撞击。",
            "de": "Räder hämmern auf eine verbogene Schienenlasche—hier rollte kürzlich etwas Schweres.",
            "ru": "Колёса бьют по погнутой накладке—недавно здесь прошло что-то тяжёлое.",
            "es": "Las ruedas golpean una junta torcida; algo pesado pasó hace poco.",
        },
    },
    "黏稠雾气": {
        "title": {
            "en": "Iron Fog",
            "zh": "黏稠雾气",
            "de": "Eisennebel",
            "ru": "Железный туман",
            "es": "Niebla de hierro",
        },
        "body_base": {
            "en": "Rust-tanged fog rolls in sheets; visibility flickers between clear and blind.",
            "zh": "风里带着铁锈味，能见度一阵好一阵坏。",
            "de": "Rostig riechender Nebel zieht in Böen; die Sicht flackert.",
            "ru": "Туман пахнет ржавчиной; видимость то улучшается, то падает.",
            "es": "La niebla huele a óxido; la visibilidad va y viene.",
        },
    },
    "折断的路标": {
        "title": {
            "en": "Broken Signpost",
            "zh": "折断的路标",
            "de": "Umgefallener Wegweiser",
            "ru": "Сломанный указатель",
            "es": "Señal caída",
        },
        "body_base": {
            "en": "An old district sign lies face-down; the painted letters are worn off.",
            "zh": "旧城区的方向标倒在地上，字迹被磨平了。",
            "de": "Ein alter Stadtteilschild liegt umgekippt; die Buchstaben sind abgewischt.",
            "ru": "Старый указатель лежит лицом вниз; буквы стёрты.",
            "es": "Una señal del barrio viejo yace boca abajo; las letras están borradas.",
        },
    },
    "求援涂鸦": {
        "title": {
            "en": "Chalk Plea",
            "zh": "求援涂鸦",
            "de": "Hilferuf in Kreide",
            "ru": "Мелом о помощи",
            "es": "Súplica con tiza",
        },
        "body_base": {
            "en": "Fresh chalk arrows on a boxcar point toward a shanty belt along the yard.",
            "zh": "车厢壁上有人用粉笔画了箭头——指向棚户区。",
            "de": "Frische Kreidepfeile auf einem Güterwagen zeigen auf Baracken am Gleis.",
            "ru": "Свежие меловые стрелки на вагоне указывают на трущобы у депо.",
            "es": "Flechas de tiza en un vagón señalan chabolas del patio.",
        },
    },
}

SEASON_HOOK_I18N: Dict[str, Dict[str, Dict[str, str]]] = {
    "融雪渗水": {
        "title": {
            "en": "Thaw Seep",
            "zh": "融雪渗水",
            "de": "Tauwasser",
            "ru": "Талая вода",
            "es": "Filtración del deshielo",
        },
        "body_base": {
            "en": "Snowmelt turns the ballast into slurry; water creeps between the ties.",
            "zh": "路基两旁积雪化成泥水，渗进枕木缝里。",
            "de": "Schmelzwasser macht den Schotterbrei; Wasser sickert zwischen den Schwellen.",
            "ru": "Талая вода превращает балласт в жижу; вода просачивается между шпалами.",
            "es": "El deshielo convierte el balasto en barro; el agua se cuela entre los traviesas.",
        },
    },
    "返青的栅栏": {
        "title": {
            "en": "Green Wire",
            "zh": "返青的栅栏",
            "de": "Grüner Zaun",
            "ru": "Зелёный забор",
            "es": "Alambrada verde",
        },
        "body_base": {
            "en": "Weeds punch through a chain-link fence as if someone walked the line yesterday.",
            "zh": "野草从铁丝网里钻出来，像是不久前才有人路过。",
            "de": "Unkraut bricht durch den Maschendraht, als wäre gestern noch jemand die Strecke gegangen.",
            "ru": "Сорняки пробиваются сквозь сетку, будто вчера здесь кто-то ходил.",
            "es": "Hierbas rompen la valla metálica como si alguien pasó ayer.",
        },
    },
    "热浪蒸腾": {
        "title": {
            "en": "Heat Shimmer",
            "zh": "热浪蒸腾",
            "de": "Hitzeflimmern",
            "ru": "Жаркая дымка",
            "es": "Calor vibrante",
        },
        "body_base": {
            "en": "Steel plates scorch to the touch; the horizon wavers like open flame.",
            "zh": "钢板烫手，远处地表在空气中晃动。",
            "de": "Stahlplatten brennen beim Berühren; der Horizont flimmert wie Flammen.",
            "ru": "Сталь обжигает; горизонт дрожит, как пламя.",
            "es": "El acero quema al tacto; el horizonte ondea como llama.",
        },
    },
    "干渴风声": {
        "title": {
            "en": "Dry Wind",
            "zh": "干渴风声",
            "de": "Trockener Wind",
            "ru": "Сухой ветер",
            "es": "Viento seco",
        },
        "body_base": {
            "en": "The wind carries zero moisture; water-tank lids are too hot to handle.",
            "zh": "风里没有一点潮气，水箱盖子烫得不敢碰。",
            "de": "Der Wind ist staubtrocken; Wassertankdeckel sind zu heiß zum Anfassen.",
            "ru": "Ветер без влаги; крышки баков слишком горячие.",
            "es": "El viento no trae humedad; las tapas de los tanques queman.",
        },
    },
    "落叶塞轨": {
        "title": {
            "en": "Leaf Jam",
            "zh": "落叶塞轨",
            "de": "Laubstau",
            "ru": "Листья на путях",
            "es": "Hojas en la vía",
        },
        "body_base": {
            "en": "Dry branches pile at a turnout, as if someone left in a hurry.",
            "zh": "枯枝堆在道岔口，像有人仓促离开。",
            "de": "Trockene Äste stauen sich an einer Weiche, als wäre jemand geflohen.",
            "ru": "Сухие ветки забили стрелку — будто кто-то ушёл впопыхах.",
            "es": "Ramas secas bloquean el desvío; alguien se marchó con prisa.",
        },
    },
    "仓房烟囱": {
        "title": {
            "en": "Silo Smoke",
            "zh": "仓房烟囱",
            "de": "Silo-Rauch",
            "ru": "Дым склада",
            "es": "Humo del silo",
        },
        "body_base": {
            "en": "Smoke rises from a grain hall—shelves inside might still hold stock.",
            "zh": "大粮仓方向有烟——也许还有未搬空的货架。",
            "de": "Rauch steigt aus einer Kornschwinge — vielleicht steht noch etwas auf den Regalen.",
            "ru": "Дым из зернохранилища — на полках может остаться запас.",
            "es": "Humo del granero; quizá queden provisiones en los estantes.",
        },
    },
    "冻结的车门": {
        "title": {
            "en": "Frozen Door",
            "zh": "冻结的车门",
            "de": "Gefrorene Tür",
            "ru": "Замёрзшая дверь",
            "es": "Puerta helada",
        },
        "body_base": {
            "en": "Ice fangs hang from a stranded coach door; the cabin inside is pitch black.",
            "zh": "一节抛锚客车门下结着冰凌，里面黑漆漆的。",
            "de": "Eiszapfen hängen an einer liegen gebliebenen Wagentür; drinnen ist Finsternis.",
            "ru": "Сосульки на двери брошенного вагона; внутри тьма.",
            "es": "Carámbanos cuelgan de un vagón varado; adentro no hay luz.",
        },
    },
    "雪窝足迹": {
        "title": {
            "en": "Snow Trail",
            "zh": "雪窝足迹",
            "de": "Schneespur",
            "ru": "След на снегу",
            "es": "Rastro en la nieve",
        },
        "body_base": {
            "en": "Footprints cross the drift toward a station—then stop mid-field.",
            "zh": "雪原上有一串走向车站的脚印，半途断了。",
            "de": "Fußspuren durchqueren die Schneewehe zur Station — und brechen ab.",
            "ru": "Следы ведут к станции по сугробам — и обрываются.",
            "es": "Huellas cruzan la nieve hacia la estación y se cortan a mitad de camino.",
        },
    },
}

YEAR_HOOK_I18N: Dict[str, Dict[str, Dict[str, str]]] = {
    "第二年茶歇": {
        "title": {
            "en": "Second-Year Pause",
            "zh": "第二年茶歇",
            "de": "Pause im zweiten Jahr",
            "ru": "Пауза второго года",
            "es": "Tregua del segundo año",
        },
        "body_base": {
            "en": "Everyone remembers last winter; more silences slip into ordinary talk.",
            "zh": "大家都记得去年冬天；对话里多了几处沉默。",
            "de": "Alle erinnern sich an den letzten Winter; mehr Pausen schleichen sich ins Gespräch.",
            "ru": "Все помнят прошлую зиму; в разговорах чаще случаются паузы.",
            "es": "Todos recuerdan el invierno pasado; hay más silencios en la charla.",
        },
    },
    "熟悉的地名": {
        "title": {
            "en": "Wrong Familiar Name",
            "zh": "熟悉的地名",
            "de": "Vertrauter falscher Name",
            "ru": "Знакомое имя",
            "es": "Nombre familiar equivocado",
        },
        "body_base": {
            "en": "A placard matches a memory—but nothing else on the skyline does.",
            "zh": "路牌上的名字和记忆对上了，却不是记忆中的样子。",
            "de": "Ein Ortsschild passt zur Erinnerung — doch sonst nichts am Horizont.",
            "ru": "Табличка совпала с памятью — но пейзаж уже другой.",
            "es": "El letrero coincide con el recuerdo, pero el paisaje no.",
        },
    },
    "长线威胁": {
        "title": {
            "en": "Long Frequency",
            "zh": "长线威胁",
            "de": "Lange Frequenz",
            "ru": "Длинная частота",
            "es": "Frecuencia larga",
        },
        "body_base": {
            "en": "Broken radio chatter uses a code you cannot decode.",
            "zh": "无线电里断续的口令——不是他们能解开的频率。",
            "de": "Funkstörgeräusche in einer Frequenz, die ihr nicht entschlüsseln könnt.",
            "ru": "По рации идёт шифр, который вы не можете разобрать.",
            "es": "La radio transmite un código que no pueden descifrar.",
        },
    },
}

ALL_HOOK_I18N: Dict[str, Dict[str, Dict[str, str]]] = {
    **HOOK_I18N,
    **SEASON_HOOK_I18N,
    **YEAR_HOOK_I18N,
}


def _general_card_paths() -> List[Path]:
    return sorted((ROOT / "general").glob("gen_*.json"))


def _season_card_paths() -> List[Path]:
    paths: List[Path] = []
    for season in ("spring", "summer", "autumn", "winter"):
        paths.extend(sorted((ROOT / "season" / season).glob("*.json")))
    return paths


def _year_card_paths() -> List[Path]:
    return sorted((ROOT / "year").glob("yr_*.json"))


@dataclass(frozen=True)
class BucketSpec:
    name: str
    csv_file: str
    card_paths: Callable[[], List[Path]]


BUCKETS: Dict[str, BucketSpec] = {
    "general": BucketSpec("general", "events_general.csv", _general_card_paths),
    "season": BucketSpec("season", "events_season.csv", _season_card_paths),
    "year": BucketSpec("year", "events_year.csv", _year_card_paths),
}


def bucket_csv_path(spec: BucketSpec) -> Path:
    return LOC_DIR / spec.csv_file


OPTION_LABELS: Dict[str, Dict[str, str]] = {
    "shelter": {
        "en": "Make room",
        "zh": "腾一张床",
        "de": "Platz schaffen",
        "ru": "Освободить койку",
        "es": "Hacer hueco",
    },
    "pass": {
        "en": "Move on",
        "zh": "鸣笛离开",
        "de": "Weiterfahren",
        "ru": "Трогаться",
        "es": "Seguir",
    },
    "share": {
        "en": "Share rations",
        "zh": "匀一点口粮",
        "de": "Rationen teilen",
        "ru": "Поделиться пайками",
        "es": "Compartir raciones",
    },
    "hoard": {
        "en": "Hold stock",
        "zh": "封仓不动",
        "de": "Vorrat halten",
        "ru": "Не трогать запас",
        "es": "Guardar reservas",
    },
    "scout": {
        "en": "Scout ahead",
        "zh": "派人摸近",
        "de": "Späher voraus",
        "ru": "Разведать впереди",
        "es": "Explorar adelante",
    },
    "detour": {
        "en": "Detour",
        "zh": "绕开这段",
        "de": "Umleitung",
        "ru": "Объехать",
        "es": "Desvío",
    },
    "brace": {
        "en": "Brace heat",
        "zh": "收紧供暖",
        "de": "Heizung anziehen",
        "ru": "Усилить обогрев",
        "es": "Subir calefacción",
    },
    "ignore": {
        "en": "Stay course",
        "zh": "按原计划走",
        "de": "Kurs halten",
        "ru": "Держать курс",
        "es": "Mantener rumbo",
    },
    "dig": {
        "en": "Pick through",
        "zh": "把废墟翻一遍",
        "de": "Trümmer durchsuchen",
        "ru": "Перебрать завалы",
        "es": "Rebuscar escombros",
    },
    "skip": {
        "en": "Skip it",
        "zh": "不耽搁",
        "de": "Überspringen",
        "ru": "Не задерживаться",
        "es": "No parar",
    },
    "talk": {
        "en": "Let them talk",
        "zh": "让几个人聊聊",
        "de": "Reden lassen",
        "ru": "Дать поговорить",
        "es": "Dejar que hablen",
    },
    "silence": {
        "en": "Stay silent",
        "zh": "继续沉默",
        "de": "Schweigen",
        "ru": "Молчать",
        "es": "Guardar silencio",
    },
}


def card_locale_keys(card: dict) -> List[Tuple[str, str]]:
    """Return (csv_key_suffix, field_group) rows for one card."""
    eid = card["id"]
    rows: List[Tuple[str, str]] = []
    for field in ("title", "body", "logLine"):
        rows.append((f"event.{eid}.{field}", field))
    for opt in card.get("options") or []:
        oid = str(opt.get("id", ""))
        if oid:
            rows.append((f"event.{eid}.opt.{oid}", f"opt.{oid}"))
    return rows


def read_locale_blob(card: dict, field: str, opt_id: Optional[str] = None) -> Dict[str, str]:
    if field.startswith("opt."):
        oid = field.split(".", 1)[1]
        for opt in card.get("options") or []:
            if opt.get("id") == oid:
                return dict(opt.get("label") or {})
        return {}
    return dict(card.get(field) or {})


def write_locale_blob(
    card: dict,
    field: str,
    locales: Dict[str, str],
) -> None:
    if field.startswith("opt."):
        oid = field.split(".", 1)[1]
        for opt in card.get("options") or []:
            if opt.get("id") == oid:
                label = opt.setdefault("label", {})
                for col in LOCALE_COLS:
                    if locales.get(col):
                        label[col] = locales[col]
                return
        return
    blob = card.setdefault(field, {})
    for col in LOCALE_COLS:
        if locales.get(col):
            blob[col] = locales[col]


def export_csv(spec: BucketSpec, path: Optional[Path] = None) -> int:
    path = path or bucket_csv_path(spec)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: List[Dict[str, str]] = []
    for card_path in spec.card_paths():
        card = json.loads(card_path.read_text(encoding="utf-8"))
        for key, field in card_locale_keys(card):
            loc = read_locale_blob(card, field)
            row = {"key": key}
            for col in LOCALE_COLS:
                row[col] = loc.get(col, "")
            rows.append(row)
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["key", *LOCALE_COLS])
        writer.writeheader()
        writer.writerows(rows)
    print(f"export [{spec.name}]: {len(rows)} rows → {path}")
    return len(rows)


def load_csv(path: Path) -> Dict[str, Dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(path)
    out: Dict[str, Dict[str, str]] = {}
    with path.open(encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh):
            key = row["key"].strip()
            out[key] = {col: (row.get(col) or "").strip() for col in LOCALE_COLS}
    return out


def import_csv(spec: BucketSpec, path: Optional[Path] = None, dry_run: bool = False) -> int:
    path = path or bucket_csv_path(spec)
    table = load_csv(path)
    updated = 0
    for card_path in spec.card_paths():
        card = json.loads(card_path.read_text(encoding="utf-8"))
        changed = False
        for key, field in card_locale_keys(card):
            loc = table.get(key)
            if not loc:
                continue
            before = json.dumps(read_locale_blob(card, field), sort_keys=True)
            write_locale_blob(card, field, loc)
            after = json.dumps(read_locale_blob(card, field), sort_keys=True)
            if before != after:
                changed = True
        if changed:
            updated += 1
            if not dry_run:
                card_path.write_text(
                    json.dumps(card, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
    print(f"import [{spec.name}]: {updated} cards updated dry_run={dry_run}")
    return updated


def validate_csv(spec: BucketSpec, path: Optional[Path] = None) -> List[str]:
    path = path or bucket_csv_path(spec)
    errs: List[str] = []
    if not path.is_file():
        return [f"missing {path}"]
    table = load_csv(path)
    expected: List[str] = []
    for card_path in spec.card_paths():
        card = json.loads(card_path.read_text(encoding="utf-8"))
        for key, _ in card_locale_keys(card):
            expected.append(key)
    missing = [k for k in expected if k not in table]
    extra = [k for k in table if k not in expected]
    for k in missing:
        errs.append(f"missing key {k}")
    for k in extra:
        errs.append(f"unknown key {k}")
    for key in expected:
        row = table.get(key, {})
        for col in LOCALE_COLS:
            if not row.get(col):
                errs.append(f"empty {col} for {key}")
    return errs


def _hook_title_zh(card: dict) -> str:
    return str(card.get("title", {}).get("zh", ""))


def seed_missing_locales(spec: BucketSpec, path: Optional[Path] = None) -> int:
    """Fill de/ru/es (and empty en) from hook + option tables; preserve per-card zh/en body."""
    path = path or bucket_csv_path(spec)
    if not path.is_file():
        export_csv(spec, path)
    table = load_csv(path)

    for card_path in spec.card_paths():
        card = json.loads(card_path.read_text(encoding="utf-8"))
        title_zh = _hook_title_zh(card)
        hook = ALL_HOOK_I18N.get(title_zh)
        body_zh = card.get("body", {}).get("zh", "")

        for key, field in card_locale_keys(card):
            row = table.setdefault(key, {"key": key, **{c: "" for c in LOCALE_COLS}})
            if field == "title" and hook:
                for col in LOCALE_COLS:
                    if not row.get(col):
                        row[col] = hook["title"][col]
            elif field == "body":
                for col in LOCALE_COLS:
                    if row.get(col):
                        continue
                    if col == "zh":
                        row[col] = body_zh
                    elif card.get("body", {}).get(col):
                        row[col] = card["body"][col]
                    elif hook:
                        row[col] = hook["body_base"][col]
            elif field == "logLine":
                t = table.get(f"event.{card['id']}.title", {})
                b = table.get(f"event.{card['id']}.body", {})
                for col in LOCALE_COLS:
                    if row.get(col):
                        continue
                    title = t.get(col, "")
                    body = b.get(col, "")
                    if col == "zh":
                        row[col] = f"【{title}】{body}" if title else body
                    elif col == "en":
                        row[col] = f"[{title}] {body}" if title else body
                    else:
                        row[col] = f"«{title}» {body}" if title else body
            elif field.startswith("opt."):
                oid = field.split(".", 1)[1]
                labels = OPTION_LABELS.get(oid, {})
                for col in LOCALE_COLS:
                    if not row.get(col):
                        if labels.get(col):
                            row[col] = labels[col]
                        elif card.get("options"):
                            for opt in card["options"]:
                                if opt.get("id") == oid:
                                    row[col] = (opt.get("label") or {}).get(col, "")

    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["key", *LOCALE_COLS])
        writer.writeheader()
        for key in sorted(table.keys()):
            row = table[key]
            writer.writerow({"key": key, **{c: row.get(c, "") for c in LOCALE_COLS}})

    print(f"seed [{spec.name}]: wrote {len(table)} rows → {path}")
    return len(table)


def _bucket_from_args(args: argparse.Namespace) -> BucketSpec:
    return BUCKETS[args.bucket]


def main() -> int:
    ap = argparse.ArgumentParser(description="Event cards ↔ localization CSV (08 五语)")
    ap.add_argument(
        "--bucket",
        choices=sorted(BUCKETS.keys()),
        default="general",
        help="general=gen_* (60); season=spr|sum|aut|win (40); year=yr_* (20)",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("export", help="JSON → CSV")
    p_imp = sub.add_parser("import", help="CSV → JSON")
    p_imp.add_argument("--dry-run", action="store_true")
    sub.add_parser("validate", help="Check CSV coverage")
    sub.add_parser("seed", help="Fill de/ru/es from hook tables into CSV")
    sub.add_parser("pipeline", help="export → seed → validate → import")
    args = ap.parse_args()
    spec = _bucket_from_args(args)

    if args.cmd == "export":
        export_csv(spec)
        return 0
    if args.cmd == "import":
        import_csv(spec, dry_run=args.dry_run)
        return 0
    if args.cmd == "validate":
        errs = validate_csv(spec)
        if errs:
            for e in errs[:40]:
                print(f"  • {e}")
            if len(errs) > 40:
                print(f"  … +{len(errs) - 40} more")
            return 1
        print(f"validate [{spec.name}]: OK")
        return 0
    if args.cmd == "seed":
        seed_missing_locales(spec)
        return 0
    if args.cmd == "pipeline":
        export_csv(spec)
        seed_missing_locales(spec)
        errs = validate_csv(spec)
        if errs:
            print("validate failed after seed; fix CSV")
            return 1
        import_csv(spec)
        errs2 = validate_csv(spec)
        if errs2:
            return 1
        print(f"pipeline [{spec.name}]: OK (CSV → JSON)")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())