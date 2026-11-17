"""Free-time forecast: aggregate ended sessions over the past 8 weeks (Python-side, no cache).

Scores per (weekday, 30-min slot): days on which a declaration overlapped the slot
divided by the number of that weekday inside the window. Slots with score >= 0.5
and >= 3 hit days are merged when contiguous. basis = history / manual / both.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from .models import HimaSession, RegularSlot

TZ = ZoneInfo("Asia/Tokyo")
SLOT_MIN = 30
SLOTS_PER_DAY = 48
PERIOD_DAYS = 56  # 8 weeks (ends today)
HIT_DAYS_MIN = 3
SCORE_MIN = 0.5

Basis = str  # "history" | "manual" | "both"


def _day_base(day: date) -> datetime:
    return datetime.combine(day, time.min, tzinfo=TZ)


def _merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Merge overlapping or adjacent [start_min, end_min) ranges."""
    merged: list[tuple[int, int]] = []
    for start, end in sorted(ranges):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def compute_forecast(db: Session, user_id: int) -> list[dict]:
    now = datetime.now(TZ)
    today = now.date()
    window_start_date = today - timedelta(days=PERIOD_DAYS - 1)
    window_start = _day_base(window_start_date)

    day_counts = [0] * 7
    day = window_start_date
    while day <= today:
        day_counts[day.weekday()] += 1
        day += timedelta(days=1)

    # 集計: (weekday, slot_index) -> 宣言が枠と重なった日集合
    hits: list[dict[int, set[date]]] = [defaultdict(set) for _ in range(7)]
    rows = (
        db.query(HimaSession.started_at, HimaSession.ended_at, HimaSession.expires_at)
        .filter(
            HimaSession.user_id == user_id,
            HimaSession.ended_at.isnot(None),
            HimaSession.started_at >= window_start,
        )
        .all()
    )
    for started_at, ended_at, expires_at in rows:
        start = started_at.astimezone(TZ)
        end = (ended_at or expires_at).astimezone(TZ)
        if end <= start:
            end = start + timedelta(minutes=1)
        day = start.date()
        last = end.date()
        while day <= last:
            base = _day_base(day)
            for slot in range(SLOTS_PER_DAY):
                slot_start = base + timedelta(minutes=SLOT_MIN * slot)
                slot_end = slot_start + timedelta(minutes=SLOT_MIN)
                if start < slot_end and end > slot_start:
                    hits[day.weekday()][slot].add(day)
            day += timedelta(days=1)

    # 候補枠 → 連続マージ
    history_by_weekday: dict[int, list[tuple[int, int, float, int]]] = {}
    for wd in range(7):
        if day_counts[wd] == 0:
            continue
        slots = sorted(
            slot
            for slot, days in hits[wd].items()
            if len(days) >= HIT_DAYS_MIN and len(days) / day_counts[wd] >= SCORE_MIN
        )
        if not slots:
            continue
        merged: list[list[int]] = []  # [start_min, end_min, slots...]
        for slot in slots:
            start, end = slot * SLOT_MIN, (slot + 1) * SLOT_MIN
            if merged and start <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], end)
                merged[-1].append(slot)
            else:
                merged.append([start, end, slot])
        history_by_weekday[wd] = [
            (m[0], m[1], round(sum(len(hits[wd][s]) / day_counts[wd] for s in m[2:]) / len(m[2:]), 3),
             min(len(hits[wd][s]) for s in m[2:]))
            for m in merged
        ]

    # regular_slots（manual）
    manual_rows = (
        db.query(RegularSlot.weekday, RegularSlot.start_min, RegularSlot.end_min)
        .filter(RegularSlot.user_id == user_id)
        .all()
    )
    manual_by_weekday: dict[int, list[tuple[int, int]]] = defaultdict(list)
    for wd, start_min, end_min in manual_rows:
        manual_by_weekday[wd].append((start_min, end_min))
    manual_merged = {wd: _merge_ranges(v) for wd, v in manual_by_weekday.items()}

    out: list[dict] = []
    for wd in range(7):
        manual_ranges = manual_merged.get(wd, [])
        for start, end, score, days in history_by_weekday.get(wd, []):
            basis: Basis = (
                "both" if any(start < m_end and end > m_start for m_start, m_end in manual_ranges) else "history"
            )
            out.append({"weekday": wd, "start_min": start, "end_min": end, "basis": basis,
                        "score": score, "days": days})
        for start, end in manual_ranges:
            if any(start < h_end and end > h_start for h_start, h_end, _, _ in history_by_weekday.get(wd, [])):
                continue  # both として済み
            out.append({"weekday": wd, "start_min": start, "end_min": end, "basis": "manual",
                        "score": 0.0, "days": 0})
    return out
