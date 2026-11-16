"""Matching: role combinations between active sessions (evaluated on declaration/extension)."""
from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import discord_rest
from .models import Match, User
from .services import has_shared_visible_guild, is_blocked, utcnow
from .vocab import ACTIVITIES

log = logging.getLogger("atsumaro.matching")

KIND = {
    ("fire", "fire"): "fire_fire",
    ("fire", "ok"): "fire_ok",
    ("ok", "fire"): "fire_ok",
    ("ok", "ok"): "ok_ok",
}
MAX_DMS_PER_DECLARATION = 3


def _dm_targets(kind: str, me_user: int, other_user: int, me_is_fire: bool) -> list[int]:
    if kind == "fire_fire":
        return [me_user, other_user]
    if kind == "fire_ok":
        return [me_user if me_is_fire else other_user]
    return [me_user, other_user]  # ok_ok


def _dm_text(kind: str, other_name: str, activity_key: str, minutes: int) -> str:
    label = ACTIVITIES.get(activity_key, activity_key)
    if kind == "fire_fire":
        return f"🔥 {other_name} さんも今ヒマ！{label}・あと{minutes}分。お互い誘い合えるかも！"
    if kind == "fire_ok":
        return f"誘えば来そうな人がいるよ：🙂 {other_name} さん（{label}・あと{minutes}分）"
    return f"🙂 お互い誘われ待ちだよ。きっかけにどうぞ：{other_name} さん（{label}・あと{minutes}分）"


def _send_dm(rest, user_id: int, content: str) -> bool:
    channel = rest.open_dm_channel(user_id)
    if channel is None:
        log.info("match DM skipped (no DM channel) user=%s", user_id)
        return False
    sent = rest.send_message(channel, content)
    if sent is None:
        log.info("match DM failed to send user=%s", user_id)
        return False
    return True


def evaluate_for_session(db: Session, session_row, rest=None) -> int:
    """Evaluate matches for the just declared/extended session. Returns DMs attempted."""
    rest = rest or discord_rest.rest
    me_user = session_row.user_id
    me_mood = session_row.mood
    if me_mood == "moon":
        return 0  # 🌙 はマッチング通知の対象にも発信にもならない

    now = utcnow()
    candidates = db.execute(
        text(
            """
            SELECT s.id AS session_id, s.user_id, s.mood, s.activity, s.expires_at,
                   (s.activity = :my_activity) AS same_activity
            FROM hima_sessions s
            WHERE s.ended_at IS NULL AND s.user_id != :uid AND s.mood != 'moon'
            ORDER BY same_activity DESC, s.expires_at ASC
            """
        ),
        {"uid": me_user, "my_activity": session_row.activity},
    ).mappings().all()

    dm_count = 0
    for cand in candidates:
        if dm_count >= MAX_DMS_PER_DECLARATION:
            break
        other_user = int(cand["user_id"])
        if not has_shared_visible_guild(db, me_user, other_user):
            continue
        if is_blocked(db, me_user, other_user):
            continue
        kind = KIND[(me_mood, cand["mood"])]
        if session_row.id < int(cand["session_id"]):
            a_id, a_user = session_row.id, me_user
            b_id, b_user = int(cand["session_id"]), other_user
        else:
            a_id, a_user = int(cand["session_id"]), other_user
            b_id, b_user = session_row.id, me_user
        exists = db.execute(
            text("SELECT 1 FROM matches WHERE session_a_id = :a AND session_b_id = :b"),
            {"a": a_id, "b": b_id},
        ).first()
        if exists:
            continue  # 同じ登録同士のペアは温度感が変わっても再通知しない
        db.add(Match(session_a_id=a_id, session_b_id=b_id, user_a=a_user, user_b=b_user, kind=kind))

        other = db.get(User, other_user)
        other_name = other.display_name if other else f"discord:{other_user}"
        cand_minutes = max(
            1, int((cand["expires_at"] - now).total_seconds() // 60)
        )
        me_is_fire = me_mood == "fire"
        for target in _dm_targets(kind, me_user, other_user, me_is_fire):
            other_of_target = other_user if target == me_user else me_user
            other_obj = db.get(User, other_of_target)
            other_of_target_name = other_obj.display_name if other_obj else f"discord:{other_of_target}"
            content = _dm_text(kind, other_of_target_name, cand["activity"], cand_minutes)
            _send_dm(rest, target, content)
            dm_count += 1
    db.commit()
    return dm_count
