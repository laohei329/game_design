# -*- coding: utf-8 -*-
"""Generate 120 event cards + _index.json. DISASTER RECOVERY ONLY — overwrites JSON.

日常维护用 sync_event_locale.py + CSV，勿对本目录已有卡全量运行。
Default status=ready (sweep/client). --draft for WIP."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO_DATA = ROOT.parent


def manifest_config_version() -> int:
    raw = json.loads((REPO_DATA / "manifest.json").read_text(encoding="utf-8"))
    return int(raw["configVersion"])

GENERAL_HOOKS = [
    ("路边信号", "有人在废轨旁举起手电。", "supply", 1.1),
    ("余烬营地", "远处有未熄尽的火，不确定还有没有幸存者。", "loot", 1.0),
    ("铁轨异响", "车轮压过变形的接头，像是刚发生过撞击。", "raid", 0.9),
    ("黏稠雾气", "风里带着铁锈味，能见度一阵好一阵坏。", "weather", 0.85),
    ("折断的路标", "旧城区的方向标倒在地上，字迹被磨平了。", "mood", 0.8),
    ("求援涂鸦", "车厢壁上有人用粉笔画了箭头——指向棚户区。", "recruit", 1.15),
]

SEASON_HOOKS = {
    "spring": [
        ("融雪渗水", "路基两旁积雪化成泥水，渗进枕木缝里。", "supply", 1.0),
        ("返青的栅栏", "野草从铁丝网里钻出来，像是不久前才有人路过。", "mood", 0.9),
    ],
    "summer": [
        ("热浪蒸腾", "钢板烫手，远处地表在空气中晃动。", "weather", 1.0),
        ("干渴风声", "风里没有一点潮气，水箱盖子烫得不敢碰。", "supply", 1.05),
    ],
    "autumn": [
        ("落叶塞轨", "枯枝堆在道岔口，像有人仓促离开。", "loot", 1.0),
        ("仓房烟囱", "大粮仓方向有烟——也许还有未搬空的货架。", "supply", 1.15),
    ],
    "winter": [
        ("冻结的车门", "一节抛锚客车门下结着冰凌，里面黑漆漆的。", "raid", 1.0),
        ("雪窝足迹", "雪原上有一串走向车站的脚印，半途断了。", "recruit", 1.1),
    ],
}

YEAR_HOOKS = [
    ("第二年茶歇", "大家都记得去年冬天；对话里多了几处沉默。", "mood", 1.0),
    ("熟悉的地名", "路牌上的名字和记忆对上了，却不是记忆中的样子。", "loot", 0.95),
    ("长线威胁", "无线电里断续的口令——不是他们能解开的频率。", "raid", 1.1),
]

# 收留配额权威名单（恰 24）；与 tags / _index 对齐
RECRUIT_IDS = frozenset(
    [f"gen_{i:03d}" for i in range(1, 61) if i % 6 == 1]
    + [
        f"{s}_{i:03d}"
        for s in ("spr", "sum", "aut", "win")
        for i in (2, 5)
    ]
    + [f"yr_{i:03d}" for i in (1, 4, 7, 10, 13, 16)]
)


def _options(event_id: str, tag: str) -> list:
    key = f"evt_{event_id}"
    if tag == "recruit":
        return [
            {
                "id": "shelter",
                "label": {"zh": "腾一张床", "en": "Make room"},
                "immediate": {"op": "recruit_roll", "targetType": "global", "args": {"p": 0.72}},
                "delayDays": 3,
                "op": "flag_set",
                "targetType": "global",
                "args": {"key": f"{key}_late", "value": True},
            },
            {
                "id": "pass",
                "label": {"zh": "鸣笛离开", "en": "Move on"},
                "delayDays": 2,
                "op": "weight_mod",
                "targetType": "segment",
                "args": {"eventTag": "raid", "delta": 0.05},
            },
        ]
    if tag == "supply":
        return [
            {
                "id": "share",
                "label": {"zh": "匀一点口粮", "en": "Share rations"},
                "immediate": {
                    "op": "grant_item",
                    "targetType": "global",
                    "args": {"res": "food", "amount": 4},
                },
                "delayDays": 2,
                "op": "mood_delta",
                "targetType": "party",
                "args": {"delta": -2},
                "capture": "snapshot",
            },
            {
                "id": "hoard",
                "label": {"zh": "封仓不动", "en": "Hold stock"},
                "delayDays": 1,
                "op": "flag_set",
                "targetType": "global",
                "args": {"key": f"{key}_hoard", "value": True},
            },
        ]
    if tag == "raid":
        return [
            {
                "id": "scout",
                "label": {"zh": "派人摸近", "en": "Scout ahead"},
                "delayDays": 1,
                "op": "loot_halve",
                "targetType": "segment",
                "args": {"ratio": 0.35},
                "capture": "live",
            },
            {
                "id": "detour",
                "label": {"zh": "绕开这段", "en": "Detour"},
                "immediate": {
                    "op": "remove_item",
                    "targetType": "global",
                    "args": {"res": "fuel", "amount": 2},
                },
            },
        ]
    if tag == "weather":
        return [
            {
                "id": "brace",
                "label": {"zh": "收紧供暖", "en": "Brace heat"},
                "immediate": {
                    "op": "grant_influence",
                    "targetType": "global",
                    "args": {
                        "id": f"event.{event_id}.temp",
                        "source": "event",
                        "tempMod": -0.35,
                        "weatherBias": {"cold_snap": 1.2},
                        "waterMod": 1.0,
                        "speedMult": 1.0,
                        "pressureAdd": 0.0,
                        "expiresSegment": 2,
                    },
                },
                "delayDays": 2,
                "op": "clear_influence",
                "targetType": "global",
                "args": {"id": f"event.{event_id}.temp"},
            },
            {
                "id": "ignore",
                "label": {"zh": "按原计划走", "en": "Stay course"},
                "delayDays": 1,
                "op": "mood_delta",
                "targetType": "party",
                "args": {"delta": -3},
                "capture": "snapshot",
            },
        ]
    if tag == "loot":
        return [
            {
                "id": "dig",
                "label": {"zh": "把废墟翻一遍", "en": "Pick through"},
                "immediate": {
                    "op": "grant_item",
                    "targetType": "global",
                    "args": {"res": "parts", "amount": 2},
                },
                "delayDays": 2,
                "op": "spawn_threat",
                "targetType": "segment",
                "args": {"threatTemplateId": "horde_small"},
            },
            {
                "id": "skip",
                "label": {"zh": "不耽搁", "en": "Skip it"},
                "delayDays": 1,
                "op": "flag_set",
                "targetType": "global",
                "args": {"key": f"{key}_skip", "value": True},
            },
        ]
    # mood default
    return [
        {
            "id": "talk",
            "label": {"zh": "让几个人聊聊", "en": "Let them talk"},
            "immediate": {
                "op": "mood_delta",
                "targetType": "party",
                "args": {"delta": 3},
            },
            "delayDays": 2,
            "op": "weight_mod",
            "targetType": "segment",
            "args": {"eventTag": "raid", "delta": 0.08},
        },
        {
            "id": "silence",
            "label": {"zh": "继续沉默", "en": "Stay silent"},
            "delayDays": 1,
            "op": "mood_delta",
            "targetType": "party",
            "args": {"delta": -4},
            "capture": "snapshot",
        },
    ]


def make_card(
    event_id: str,
    bucket: str,
    title_zh: str,
    body_zh: str,
    tag: str,
    weight: float,
    *,
    status: str,
    season: str | None = None,
    min_year: int | None = None,
) -> dict:
    is_recruit = event_id in RECRUIT_IDS
    # 钩子主 tag=recruit 但不在配额名单 → 降为 mood，避免超员
    if tag == "recruit" and not is_recruit:
        tag = "mood"
    if is_recruit:
        tags = ["recruit"] if tag == "recruit" else [tag, "recruit"]
        option_tag = "recruit"
    else:
        tags = [tag]
        option_tag = tag
    cv = manifest_config_version()
    return {
        "configVersion": cv,
        "id": event_id,
        "status": status,
        "bucket": bucket,
        "season": season,
        "minYear": min_year,
        "weightEventId": f"evt_{option_tag}",
        "weight": weight,
        "yieldScale": 1.0,
        "tags": tags,
        "title": {"zh": title_zh, "en": title_zh},
        "body": {"zh": body_zh, "en": body_zh},
        "logLine": {"zh": f"【{title_zh}】{body_zh}", "en": f"[{title_zh}] {body_zh}"},
        "options": _options(event_id, option_tag),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--draft", action="store_true", help="emit status=draft (WIP copy)")
    args = ap.parse_args()
    card_status = "draft" if args.draft else "ready"
    index_status = "draft_cards" if args.draft else "ready_cards"
    recruit = sorted(RECRUIT_IDS)

    general_ids: list[str] = []
    for i in range(1, 61):
        eid = f"gen_{i:03d}"
        general_ids.append(eid)
        title, body, tag, weight = GENERAL_HOOKS[(i - 1) % len(GENERAL_HOOKS)]
        card = make_card(eid, "general", title, body, tag, weight, status=card_status)
        path = ROOT / "general" / f"{eid}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(card, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    season_ids: dict[str, list[str]] = {}
    for season in ("spring", "summer", "autumn", "winter"):
        ids: list[str] = []
        hooks = SEASON_HOOKS[season]
        for i in range(1, 11):
            eid = f"{season[:3]}_{i:03d}"
            ids.append(eid)
            title, body, tag, weight = hooks[(i - 1) % len(hooks)]
            card = make_card(
                eid, "season", title, body, tag, weight, status=card_status, season=season
            )
            path = ROOT / "season" / season / f"{eid}.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(card, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        season_ids[season] = ids

    year_ids: list[str] = []
    for i in range(1, 21):
        eid = f"yr_{i:03d}"
        year_ids.append(eid)
        title, body, tag, weight = YEAR_HOOKS[(i - 1) % len(YEAR_HOOKS)]
        min_year = 3 if i > 10 else 2
        card = make_card(
            eid, "year", title, body, tag, weight, status=card_status, min_year=min_year
        )
        path = ROOT / "year" / f"{eid}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(card, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    cv = manifest_config_version()
    index = {
        "configVersion": cv,
        "authority": "modules/06-region-events.md §2.1 · modules/09-data-platform.md",
        "status": index_status,
        "targetTotal": 120,
        "buckets": {
            "general": {
                "quota": 60,
                "description": "全年可抽 · 与季节无关",
                "filePattern": "events/general/{eventId}.json",
                "eventIds": general_ids,
            },
            "season": {
                "quota": 40,
                "description": "季节池 · 各季 10",
                "filePattern": "events/season/{season}/{eventId}.json",
                "bySeason": {s: {"quota": 10, "eventIds": season_ids[s]} for s in season_ids},
            },
            "year": {
                "quota": 20,
                "description": "年份门槛 · 年≥2/≥3",
                "filePattern": "events/year/{eventId}.json",
                "eventIds": year_ids,
            },
        },
        "tags": {
            "recruit": {
                "targetCount": 24,
                "description": "收留类 · 可跨桶",
                "eventIds": recruit,
            }
        },
        "cardSchema": {
            "required": ["id", "weightEventId", "weight", "yieldScale", "options"],
            "options": {
                "min": 2,
                "max": 4,
                "forbidPureReward": True,
                "delayConsequenceRequired": True,
            },
            "opsAuthority": "modules/09-data-platform.md §3",
        },
        "notes": "ready=阶段二可接；单卡改稿用 --draft 重生或手改 status",
    }
    (ROOT / "_index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote 120 cards status={card_status}; recruit tags={len(recruit)}")


if __name__ == "__main__":
    main()