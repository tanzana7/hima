"""Worker pass: suggest declarations 15 min before a forecast / regular slot."""
from __future__ import annotations

import logging
from datetime import datetime

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import discord_rest
from .forecast import TZ, compute_forecast
from .models import SuggestionLog, User
from .push import send_push
from .services import active_session, utcnow

log = logging.getLogger("atsumaro.suggestions")

SUGGEST_EVERY_TICKS = 30  # 30s tick × 30 = 15 min


def suggest_components() -> list:
    return [[{"type": 2, "style": 1, "label": "このまま宣言する", "custom_id": "atsumaro:suggest:declare"}]]


def suggestion_pass(db: Session, rest=None, now: datetime | None = None) -> int:
    """1回の判定。戻り値は送信した提案の件数。"""
    rest = rest or discord_rest.rest
    now = now or utcnow()
    local = now.astimezone(TZ)
    today = local.date()
    now_min = local.hour * 60 + local.minute
    sent = 0
    for (uid,) in db.query(User.id).all():
        for slot in compute_forecast(db, uid):
            if slot["weekday"] != today.weekday():
                continue
            start = slot["start_min"]
            if not (start - 15 <= now_min < start):
                continue  # 開始15分前の窓外
            if active_session(db, uid) is not None:
                continue  # 宣言中は送らない
            exists = db.execute(
                text(
                    "SELECT 1 FROM suggestion_log WHERE user_id = :u AND slot_date = :d AND start_min = :s"
                ),
                {"u": uid, "d": today, "s": start},
            ).first()
            if exists:
                continue  # 同じ枠・同じ日は1回だけ
            user = db.get(User, uid)
            if user is not None and not user.suggest_dm:
                continue  # 提案オプトアウト（suggest_dm=false）：DM・プッシュとも送らず、log も書かない。
                # log を書かないので、同じ枠の途中で true に戻せばその後のパスで送られる
            hhmm = f"{start // 60:02d}:{start % 60:02d}"
            if rest is not None:
                channel = rest.open_dm_channel(uid)
                if channel is not None:
                    rest.send_message(
                        channel,
                        f"そろそろヒマな時間じゃない？ {hhmm} 頃のあなたのいつもの時間だよ。このまま宣言する？",
                        components=suggest_components(),
                    )
            send_push(db, uid, "⏰ ヒマな時間かも", f"そろそろ {hhmm} のヒマ時間だよ。宣言する？")
            db.add(SuggestionLog(user_id=uid, slot_date=today, weekday=slot["weekday"],
                                 start_min=start, sent_at=now))
            db.commit()
            sent += 1
    return sent
