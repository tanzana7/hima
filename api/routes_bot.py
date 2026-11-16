"""Bot→API endpoints (all require the Bot bearer secret). Thin wrappers over the domain layer."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text

from . import discord_rest, domain, notify
from .auth import require_bot_secret
from .db import SessionLocal
from .models import Block, Guild, User
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
from .services import upsert_membership, upsert_user
from .notify import count_visible_active_sessions

router = APIRouter(prefix="/bot", dependencies=[Depends(require_bot_secret)])


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
    with SessionLocal() as db:
        return domain.declare_session(
            db,
            user_id=body.user_id,
            mood=body.mood,
            activity=body.activity,
            note=body.note,
            minutes=body.minutes,
            source="manual",  # Bot 経由の宣言は常に manual
            display_name=body.display_name,
            guild_id=body.guild_id,
            rest=discord_rest.rest,
        )


@router.delete("/sessions")
def end_session(body: EndSessionIn) -> dict:
    with SessionLocal() as db:
        return domain.end_session(db, body.user_id, rest=discord_rest.rest)


# ------------------------------------------------------------------ board


@router.get("/board")
def board(guild_id: int = Query(...), user_id: int = Query(...)) -> dict:
    with SessionLocal() as db:
        if db.get(Guild, guild_id) is None:
            raise HTTPException(status_code=404, detail="guild not found")
        return domain.board_for_guild(db, guild_id=guild_id, viewer_id=user_id)


# ------------------------------------------------------------------ knocks


@router.post("/knocks/results/seen")
def knock_results_seen(body: ResultsSeenIn) -> dict:
    with SessionLocal() as db:
        marked = domain.mark_results_seen(db, body.user_id)
        return {"user_id": body.user_id, "marked": marked}


@router.post("/knocks")
def create_knock(body: KnockIn) -> dict:
    with SessionLocal() as db:
        return domain.create_knock(db, from_user=body.from_user, to_user=body.to_user, template=body.template)


@router.post("/knocks/{knock_id}/reply")
def knock_reply(knock_id: int, body: ReplyIn) -> dict:
    with SessionLocal() as db:
        return domain.reply_knock(db, knock_id, user_id=body.user_id, action=body.action)


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
