"""Shared domain operations used by both the Bot and App routes (single implementation)."""
from __future__ import annotations

from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import text

from . import matching, notify
from .models import HimaSession, Knock, User
from .push import send_push
from .services import (
    active_session,
    blocked_ids,
    has_shared_visible_guild,
    is_blocked,
    upsert_membership,
    upsert_user,
    utcnow,
    visible_guild_ids,
)
from .vocab import ACTIVITIES, HIMA_SOURCES, MOODS

ACTION_STATUS = {"accept": "accepted", "later": "later", "pass": "passed"}
RESULT_LABELS = {"accepted": "いいよ！", "later": "あとで", "passed": "今回はパス"}
COOLDOWN_SECONDS = 300


def declare_session(
    db,
    *,
    user_id: int,
    mood: str,
    activity: str,
    note: str | None,
    minutes: int,
    source: str,
    display_name: str | None = None,
    guild_id: int | None = None,
    rest=None,
) -> dict:
    """宣言（新規 or 延長）。マッチング評価・見守りキュー・人数表示トピック更新も行う。"""
    if mood not in MOODS:
        raise HTTPException(status_code=400, detail="invalid mood")
    if activity not in ACTIVITIES:
        raise HTTPException(status_code=400, detail="invalid activity")
    if source not in HIMA_SOURCES:
        raise HTTPException(status_code=400, detail="invalid source")
    minutes = max(1, min(1440, minutes))
    now = utcnow()
    expires_at = now + timedelta(minutes=minutes)
    upsert_user(db, user_id, display_name)
    if guild_id is not None:
        upsert_membership(db, guild_id, user_id)
    row = active_session(db, user_id)
    created = row is None
    if row is None:
        row = HimaSession(
            user_id=user_id,
            mood=mood,
            activity=activity,
            note=note,
            source=source,
            started_at=now,
            expires_at=expires_at,
        )
        db.add(row)
        db.flush()
    else:  # 延長: 同じ行を更新（ID不変）
        row.mood = mood
        row.activity = activity
        row.note = note
        row.expires_at = expires_at
    db.commit()
    matching.evaluate_for_session(db, row, rest=rest)
    notify.enqueue_watchers(db, row)
    notify.update_counters_for_user(db, user_id, rest=rest)
    return {"session_id": row.id, "created": created, "expires_at": row.expires_at.isoformat()}


def end_session(db, user_id: int, rest=None) -> dict:
    """有効セッション終了。宛ノックを expired にし、人数表示トピックを更新する。"""
    row = active_session(db, user_id)
    ended = row is not None
    if ended:
        row.ended_at = utcnow()
    db.commit()
    db.execute(
        text("UPDATE knocks SET status = 'expired' WHERE to_user = :u AND status = 'sent'"),
        {"u": user_id},
    )
    db.commit()
    notify.update_counters_for_user(db, user_id, rest=rest)
    return {"user_id": user_id, "ended": ended}


def create_knock(db, *, from_user: int, to_user: int, template: str, rest=None) -> dict:
    if from_user == to_user:
        raise HTTPException(status_code=400, detail="cannot knock yourself")
    if active_session(db, to_user) is None:
        raise HTTPException(status_code=404, detail="target has no active session")
    if not has_shared_visible_guild(db, from_user, to_user):
        raise HTTPException(status_code=404, detail="no shared visible guild")
    if is_blocked(db, from_user, to_user):
        raise HTTPException(status_code=403, detail="blocked")
    cooldown = db.execute(
        text(
            """
            SELECT 1 FROM knocks
            WHERE created_at > now() - (:secs || ' seconds')::interval
              AND ((from_user = :f AND to_user = :t) OR (from_user = :t AND to_user = :f))
            LIMIT 1
            """
        ),
        {"secs": COOLDOWN_SECONDS, "f": from_user, "t": to_user},
    ).first()
    if cooldown:
        raise HTTPException(status_code=409, detail="knock cooldown (5 min per pair)")
    knock = Knock(from_user=from_user, to_user=to_user, template=template, status="sent")
    db.add(knock)
    db.commit()
    sender = db.get(User, from_user)
    sender_name = sender.display_name if sender else f"discord:{from_user}"
    send_push(db, to_user, "🚪 ノックが届いたよ！", f"{sender_name} さんが「{template}」")
    return {"id": knock.id, "from_user": knock.from_user, "to_user": knock.to_user, "status": knock.status}


def reply_knock(db, knock_id: int, user_id: int, action: str, rest=None) -> dict:
    if action not in ACTION_STATUS:
        raise HTTPException(status_code=400, detail="invalid action")
    knock = db.get(Knock, knock_id)
    if knock is None:
        raise HTTPException(status_code=404, detail="knock not found")
    if knock.to_user != user_id:
        raise HTTPException(status_code=403, detail="not the knock receiver")
    if knock.status != "sent":
        raise HTTPException(status_code=409, detail="already answered")
    knock.status = ACTION_STATUS[action]
    knock.responded_at = utcnow()
    db.commit()
    receiver = db.get(User, knock.to_user)
    receiver_name = receiver.display_name if receiver else f"discord:{knock.to_user}"
    label = RESULT_LABELS[knock.status]
    send_push(db, knock.from_user, "🔔 返事が届いたよ！", f"{receiver_name} さんの返事：「{label}」")
    return {"id": knock.id, "status": knock.status, "responded_at": knock.responded_at.isoformat()}


def mark_results_seen(db, user_id: int) -> int:
    res = db.execute(
        text(
            """
            UPDATE knocks SET result_seen_at = now()
            WHERE from_user = :u AND status != 'sent' AND result_seen_at IS NULL
            """
        ),
        {"u": user_id},
    )
    db.commit()
    return res.rowcount or 0


def _remaining_minutes(expires_at) -> int:
    return max(0, int((expires_at - utcnow()).total_seconds() // 60))


def _inbox_and_results(db, viewer_id: int, viewer_mood: str | None) -> tuple[list[dict], list[dict]]:
    inbox = []
    inbox_rows = db.execute(
        text(
            """
            SELECT k.id, k.from_user, k.template, k.created_at
            FROM knocks k
            WHERE k.to_user = :u AND k.status = 'sent'
            ORDER BY k.created_at DESC
            LIMIT 5
            """
        ),
        {"u": viewer_id},
    ).mappings().all()
    for k in inbox_rows:
        sender = db.get(User, int(k["from_user"]))
        inbox.append(
            {
                "id": int(k["id"]),
                "from_user": int(k["from_user"]),
                "from_display_name": sender.display_name if sender else f"discord:{k['from_user']}",
                "template": k["template"],
                "created_at": k["created_at"].isoformat(),
                # 宛先（受信者）が現在 🌙 の有効セッションを持つときだけ true
                "to_moon": viewer_mood == "moon",
            }
        )

    results = []
    result_rows = db.execute(
        text(
            """
            SELECT k.id, k.to_user, k.template, k.status, k.responded_at
            FROM knocks k
            WHERE k.from_user = :u AND k.status != 'sent' AND k.result_seen_at IS NULL
            ORDER BY k.created_at DESC
            """
        ),
        {"u": viewer_id},
    ).mappings().all()
    for k in result_rows:
        target = db.get(User, int(k["to_user"]))
        results.append(
            {
                "id": int(k["id"]),
                "to_user": int(k["to_user"]),
                "to_display_name": target.display_name if target else f"discord:{k['to_user']}",
                "template": k["template"],
                "status": k["status"],
                "responded_at": k["responded_at"].isoformat() if k["responded_at"] else None,
            }
        )
    return inbox, results


def board_for_guild(db, *, guild_id: int, viewer_id: int) -> dict:
    """単一ギルドの掲示板（Bot 向け）。共有可視・ブロック除外・source 非表示。"""
    viewer_active = active_session(db, viewer_id)
    viewer_mood = viewer_active.mood if viewer_active else None
    hidden = blocked_ids(db, viewer_id)

    rows = db.execute(
        text(
            """
            SELECT s.user_id, u.display_name, s.mood, s.activity, s.note, s.expires_at
            FROM hima_sessions s
            JOIN users u ON u.id = s.user_id
            JOIN memberships m ON m.user_id = s.user_id AND m.guild_id = :g AND m.visible = true
            WHERE s.ended_at IS NULL
            ORDER BY s.expires_at ASC
            """
        ),
        {"g": guild_id},
    ).mappings().all()
    sessions_out = []
    for r in rows:
        uid = int(r["user_id"])
        if uid != viewer_id and uid in hidden:
            continue  # ブロック関係はお互い見えない
        sessions_out.append(
            {
                "user_id": uid,
                "display_name": r["display_name"],
                "mood": r["mood"],
                "activity": r["activity"],
                "note": r["note"],
                "remaining_minutes": _remaining_minutes(r["expires_at"]),
                "expires_at": r["expires_at"].isoformat(),
            }
        )

    inbox, results = _inbox_and_results(db, viewer_id, viewer_mood)
    viewer = db.get(User, viewer_id)
    return {
        "guild_id": guild_id,
        "viewer_id": viewer_id,
        "viewer": {"user_id": viewer_id, "notify_on_hima": bool(viewer.notify_on_hima) if viewer else False},
        "sessions": sessions_out,
        "inbox": inbox,
        "results": results,
    }


def cross_guild_board(db, viewer_id: int) -> dict:
    """アプリ向け：自分が member の全サーバーを横断した掲示板。各行に shared_guild_ids を付ける。"""
    viewer_active = active_session(db, viewer_id)
    viewer_mood = viewer_active.mood if viewer_active else None
    my_guilds = set(visible_guild_ids(db, viewer_id))
    hidden = blocked_ids(db, viewer_id)

    rows = db.execute(
        text(
            """
            SELECT s.user_id, u.display_name, s.mood, s.activity, s.note, s.expires_at
            FROM hima_sessions s
            JOIN users u ON u.id = s.user_id
            WHERE s.ended_at IS NULL
            ORDER BY s.expires_at ASC
            """
        )
    ).mappings().all()
    sessions_out = []
    for r in rows:
        uid = int(r["user_id"])
        if uid == viewer_id:
            shared = sorted(my_guilds)
        else:
            if uid in hidden:
                continue
            shared = sorted(my_guilds & set(visible_guild_ids(db, uid)))
            if not shared:
                continue  # 共通サーバーがなければ見えない
        sessions_out.append(
            {
                "user_id": uid,
                "display_name": r["display_name"],
                "mood": r["mood"],
                "activity": r["activity"],
                "note": r["note"],
                "remaining_minutes": _remaining_minutes(r["expires_at"]),
                "expires_at": r["expires_at"].isoformat(),
                "shared_guild_ids": shared,
            }
        )

    inbox, results = _inbox_and_results(db, viewer_id, viewer_mood)
    return {"viewer_id": viewer_id, "sessions": sessions_out, "inbox": inbox, "results": results}
