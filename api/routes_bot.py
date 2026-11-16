"""Bot→API endpoints (all require the Bot bearer secret)."""
from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import text

from . import discord_rest, matching, notify
from .auth import require_bot_secret
from .db import SessionLocal
from .models import Block, Guild, HimaSession, Knock, Membership, User
from .schemas import (
    BlockIn,
    EndSessionIn,
    KnockIn,
    ResultsSeenIn,
    ReplyIn,
    SessionIn,
    SettingsIn,
    SetupIn,
    VisibilityIn,
)
from .services import (
    active_session,
    blocked_ids,
    has_shared_visible_guild,
    is_blocked,
    upsert_membership,
    upsert_user,
    utcnow,
)
from .notify import count_visible_active_sessions

from .vocab import ACTIVITIES, MOODS

router = APIRouter(prefix="/bot", dependencies=[Depends(require_bot_secret)])

ACTION_STATUS = {"accept": "accepted", "later": "later", "pass": "passed"}
COOLDOWN_SECONDS = 300


def _remaining_minutes(expires_at) -> int:
    return max(0, int((expires_at - utcnow()).total_seconds() // 60))


# ------------------------------------------------------------------ guild setup


@router.post("/guilds/{guild_id}/setup")
def guild_setup(guild_id: int, body: SetupIn) -> dict:
    with SessionLocal() as db:
        guild = db.get(Guild, guild_id)
        if guild is None:
            guild = Guild(id=guild_id, name=body.name)
            db.add(guild)
        else:
            guild.name = body.name
        db.flush()
        counter = discord_rest.rest.send_message(body.channel_id, notify.COUNTER_FORMAT.format(n=0))
        panel = discord_rest.rest.send_message(
            body.channel_id, discord_rest.PANEL_CONTENT, components=discord_rest.panel_components()
        )
        guild.list_channel_id = body.channel_id
        guild.list_message_id = int(counter["id"]) if counter else None
        guild.panel_message_id = int(panel["id"]) if panel else None
        db.commit()
        return {
            "guild_id": guild_id,
            "counter_message_id": guild.list_message_id,
            "panel_message_id": guild.panel_message_id,
        }


@router.post("/guilds/{guild_id}/teardown")
def guild_teardown(guild_id: int) -> dict:
    with SessionLocal() as db:
        guild = db.get(Guild, guild_id)
        if guild is None:
            raise HTTPException(status_code=404, detail="guild not found")
        if guild.list_message_id is not None and guild.list_channel_id is not None:
            discord_rest.rest.delete_message(guild.list_channel_id, guild.list_message_id)
        if guild.panel_message_id is not None and guild.list_channel_id is not None:
            discord_rest.rest.delete_message(guild.list_channel_id, guild.panel_message_id)
        guild.list_message_id = None
        guild.panel_message_id = None
        db.commit()
        return {"guild_id": guild_id, "torn_down": True}


# ------------------------------------------------------------------ sessions


@router.post("/sessions")
def declare_session(body: SessionIn) -> dict:
    if body.mood not in MOODS:
        raise HTTPException(status_code=400, detail="invalid mood")
    if body.activity not in ACTIVITIES:
        raise HTTPException(status_code=400, detail="invalid activity")
    minutes = max(1, min(1440, body.minutes))
    now = utcnow()
    expires_at = now + timedelta(minutes=minutes)
    with SessionLocal() as db:
        upsert_user(db, body.user_id, body.display_name)
        upsert_membership(db, body.guild_id, body.user_id)
        row = active_session(db, body.user_id)
        created = row is None
        if row is None:
            row = HimaSession(
                user_id=body.user_id,
                mood=body.mood,
                activity=body.activity,
                note=body.note,
                source="manual",
                started_at=now,
                expires_at=expires_at,
            )
            db.add(row)
            db.flush()
        else:  # 延長: 同じ行を更新（ID不変）
            row.mood = body.mood
            row.activity = body.activity
            row.note = body.note
            row.expires_at = expires_at
        db.commit()
        matching.evaluate_for_session(db, row, rest=discord_rest.rest)
        notify.enqueue_watchers(db, row)
        notify.update_counters_for_user(db, body.user_id, rest=discord_rest.rest)
        return {
            "session_id": row.id,
            "created": created,
            "expires_at": row.expires_at.isoformat(),
        }


@router.delete("/sessions")
def end_session(body: EndSessionIn) -> dict:
    now = utcnow()
    with SessionLocal() as db:
        row = active_session(db, body.user_id)
        ended = row is not None
        if ended:
            row.ended_at = now
        db.commit()
        # その人宛の未返答ノックは expired にする
        db.execute(
            text("UPDATE knocks SET status = 'expired' WHERE to_user = :u AND status = 'sent'"),
            {"u": body.user_id},
        )
        db.commit()
        notify.update_counters_for_user(db, body.user_id, rest=discord_rest.rest)
        return {"user_id": body.user_id, "ended": ended}


# ------------------------------------------------------------------ board


@router.get("/board")
def board(guild_id: int = Query(...), user_id: int = Query(...)) -> dict:
    with SessionLocal() as db:
        if db.get(Guild, guild_id) is None:
            raise HTTPException(status_code=404, detail="guild not found")
        viewer_active = active_session(db, user_id)
        viewer_mood = viewer_active.mood if viewer_active else None
        hidden = blocked_ids(db, user_id)

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
            if uid != user_id and uid in hidden:
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
            {"u": user_id},
        ).mappings().all()
        inbox = []
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

        result_rows = db.execute(
            text(
                """
                SELECT k.id, k.to_user, k.template, k.status, k.responded_at
                FROM knocks k
                WHERE k.from_user = :u AND k.status != 'sent' AND k.result_seen_at IS NULL
                ORDER BY k.created_at DESC
                """
            ),
            {"u": user_id},
        ).mappings().all()
        results = []
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

        viewer = db.get(User, user_id)
        return {
            "guild_id": guild_id,
            "viewer_id": user_id,
            "viewer": {"user_id": user_id, "notify_on_hima": bool(viewer.notify_on_hima) if viewer else False},
            "sessions": sessions_out,
            "inbox": inbox,
            "results": results,
        }


# ------------------------------------------------------------------ knocks


@router.post("/knocks/results/seen")
def knock_results_seen(body: ResultsSeenIn) -> dict:
    with SessionLocal() as db:
        res = db.execute(
            text(
                """
                UPDATE knocks SET result_seen_at = now()
                WHERE from_user = :u AND status != 'sent' AND result_seen_at IS NULL
                """
            ),
            {"u": body.user_id},
        )
        db.commit()
        return {"user_id": body.user_id, "marked": res.rowcount or 0}


@router.post("/knocks")
def create_knock(body: KnockIn) -> dict:
    if body.from_user == body.to_user:
        raise HTTPException(status_code=400, detail="cannot knock yourself")
    now = utcnow()
    with SessionLocal() as db:
        if active_session(db, body.to_user) is None:
            raise HTTPException(status_code=404, detail="target has no active session")
        if not has_shared_visible_guild(db, body.from_user, body.to_user):
            raise HTTPException(status_code=404, detail="no shared visible guild")
        if is_blocked(db, body.from_user, body.to_user):
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
            {"secs": COOLDOWN_SECONDS, "f": body.from_user, "t": body.to_user},
        ).first()
        if cooldown:
            raise HTTPException(status_code=409, detail="knock cooldown (5 min per pair)")
        knock = Knock(
            from_user=body.from_user, to_user=body.to_user, template=body.template, status="sent"
        )
        db.add(knock)
        db.commit()
        return {"id": knock.id, "from_user": knock.from_user, "to_user": knock.to_user, "status": knock.status}


@router.post("/knocks/{knock_id}/reply")
def knock_reply(knock_id: int, body: ReplyIn) -> dict:
    if body.action not in ACTION_STATUS:
        raise HTTPException(status_code=400, detail="invalid action")
    with SessionLocal() as db:
        knock = db.get(Knock, knock_id)
        if knock is None:
            raise HTTPException(status_code=404, detail="knock not found")
        if knock.to_user != body.user_id:
            raise HTTPException(status_code=403, detail="not the knock receiver")
        if knock.status != "sent":
            raise HTTPException(status_code=409, detail="already answered")
        knock.status = ACTION_STATUS[body.action]
        knock.responded_at = utcnow()
        db.commit()
        return {"id": knock.id, "status": knock.status, "responded_at": knock.responded_at.isoformat()}


# ------------------------------------------------------------------ blocks


@router.post("/blocks")
def add_block(body: BlockIn) -> dict:
    if body.user_id == body.blocked_user_id:
        raise HTTPException(status_code=400, detail="cannot block yourself")
    with SessionLocal() as db:
        exists = db.get(Block, (body.user_id, body.blocked_user_id))
        if exists is None:
            db.add(Block(blocker_id=body.user_id, blocked_id=body.blocked_user_id))
            db.commit()
        return {"user_id": body.user_id, "blocked_user_id": body.blocked_user_id, "blocked": True}


@router.delete("/blocks")
def remove_block(body: BlockIn) -> dict:
    with SessionLocal() as db:
        row = db.get(Block, (body.user_id, body.blocked_user_id))
        removed = row is not None
        if removed:
            db.delete(row)
            db.commit()
        return {"user_id": body.user_id, "blocked_user_id": body.blocked_user_id, "removed": removed}


@router.get("/blocks")
def list_blocks(user_id: int = Query(...)) -> dict:
    with SessionLocal() as db:
        rows = db.execute(
            text("SELECT blocked_id FROM blocks WHERE blocker_id = :u ORDER BY blocked_id"),
            {"u": user_id},
        ).scalars().all()
        return {"user_id": user_id, "blocked": [int(x) for x in rows]}


# ------------------------------------------------------------------ users / memberships


@router.put("/users/{user_id}/settings")
def user_settings(user_id: int, body: SettingsIn) -> dict:
    with SessionLocal() as db:
        upsert_user(db, user_id)
        user = db.get(User, user_id)
        user.notify_on_hima = body.notify_on_hima
        db.commit()
        return {"user_id": user_id, "notify_on_hima": user.notify_on_hima}


@router.put("/memberships/visibility")
def membership_visibility(body: VisibilityIn) -> dict:
    with SessionLocal() as db:
        if db.get(Guild, body.guild_id) is None:
            raise HTTPException(status_code=404, detail="guild not found")
        upsert_user(db, body.user_id)
        m = upsert_membership(db, body.guild_id, body.user_id, visible=body.visible)
        db.commit()
        notify.update_counter_for_guild(db, body.guild_id, rest=discord_rest.rest)
        return {"guild_id": body.guild_id, "user_id": body.user_id, "visible": m.visible}


@router.get("/guilds/{guild_id}/count")
def guild_count(guild_id: int) -> dict:
    with SessionLocal() as db:
        if db.get(Guild, guild_id) is None:
            raise HTTPException(status_code=404, detail="guild not found")
        return {"guild_id": guild_id, "count": count_visible_active_sessions(db, guild_id)}
