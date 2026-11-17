"""Counter messages and watch (見守り) notifications."""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import discord_rest
from .db import SessionLocal
from .models import Guild, WatchQueue
from .services import is_blocked, utcnow, visible_guild_ids

log = logging.getLogger("atsumaro.notify")

FLUSH_INTERVAL_TICKS = 6  # 30s tick × 6 = 3 minutes


# ------------------------------------------------------------------ count (debug)


def count_visible_active_sessions(db: Session, guild_id: int) -> int:
    return int(
        db.execute(
            text(
                """
                SELECT COUNT(DISTINCT s.user_id)
                FROM hima_sessions s
                JOIN memberships m
                  ON m.user_id = s.user_id AND m.guild_id = :g AND m.visible = true
                WHERE s.ended_at IS NULL
                """
            ),
            {"g": guild_id},
        ).scalar_one()
    )


# ------------------------------------------------------------------ watch


def enqueue_watchers(db: Session, session_row) -> int:
    """Queue a watch notification for notify_on_hima users who can see the declarer."""
    declarer = session_row.user_id
    guild_ids = visible_guild_ids(db, declarer)
    if not guild_ids:
        return 0
    placeholders = ",".join(str(int(g)) for g in guild_ids)
    watchers = db.execute(
        text(
            f"""
            SELECT DISTINCT u.id
            FROM users u
            JOIN memberships m ON m.user_id = u.id AND m.visible = true
                AND m.guild_id IN ({placeholders})
            WHERE u.notify_on_hima = true AND u.id != :uid
            """
        ),
        {"uid": declarer},
    ).scalars().all()
    added = 0
    for watcher in watchers:
        if is_blocked(db, declarer, int(watcher)):
            continue
        exists = (
            db.query(WatchQueue)
            .filter(
                WatchQueue.watcher_id == int(watcher),
                WatchQueue.session_id == session_row.id,
                WatchQueue.sent_at.is_(None),
            )
            .first()
        )
        if exists:
            continue
        db.add(WatchQueue(watcher_id=int(watcher), session_id=session_row.id))
        added += 1
    db.commit()
    return added


def flush_watch_queue(rest=None) -> int:
    """Send one grouped DM per watcher for unsent queue rows (worker, every 3 min)."""
    rest = rest or discord_rest.rest
    notified = 0
    with SessionLocal() as db:
        rows = db.execute(
            text(
                """
                SELECT w.id AS queue_id, w.watcher_id, w.session_id, s.user_id AS session_user,
                       u.display_name
                FROM watch_queue w
                JOIN hima_sessions s ON s.id = w.session_id
                JOIN users u ON u.id = s.user_id
                WHERE w.sent_at IS NULL
                ORDER BY w.watcher_id, w.created_at
                """
            )
        ).mappings().all()
        by_watcher: dict[int, list[tuple[int, str]]] = {}
        for r in rows:
            watcher = int(r["watcher_id"])
            if is_blocked(db, watcher, int(r["session_user"])):
                continue  # 通知時点でブロックされたらスキップ（次回も同じ挙動）
            by_watcher.setdefault(watcher, []).append((int(r["queue_id"]), r["display_name"]))
        now = utcnow()
        for watcher, items in by_watcher.items():
            names = "、".join(name for _, name in items)
            content = f"👀 ヒマな人が出たよ：{names}（{len(items)}人）"
            channel = rest.open_dm_channel(watcher)
            if channel is None or rest.send_message(channel, content) is None:
                log.info("watch DM not delivered watcher=%s (kept in queue)", watcher)
                continue
            db.execute(
                text("UPDATE watch_queue SET sent_at = :now WHERE id = ANY(:ids)"),
                {"now": now, "ids": [qid for qid, _ in items]},
            )
            notified += 1
        db.commit()
    return notified
