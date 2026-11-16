"""App→API endpoints (all require the app JWT). The user id always comes from the JWT."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import text

from . import discord_oauth, discord_rest, domain, notify
from .auth import issue_app_token, require_app_user
from .db import SessionLocal
from .models import Block, Device, Guild, User
from .schemas import (
    AppBlockIn,
    AppKnockIn,
    AppSessionIn,
    AppSettingsIn,
    AppVisibilityIn,
    AuthIn,
    DeviceDeleteIn,
    DeviceIn,
    ReplyIn,
)
from .services import active_session, upsert_membership, upsert_user, utcnow
from .vocab import MOODS

auth_router = APIRouter(prefix="/auth")
app_router = APIRouter(prefix="/app", dependencies=[Depends(require_app_user)])


# ------------------------------------------------------------------ /auth


@auth_router.post("/discord")
def auth_discord(body: AuthIn) -> dict:
    try:
        tokens = discord_oauth.exchange_code(body.code, body.redirect_uri, body.code_verifier)
        access = tokens.get("access_token")
        if not access:
            raise HTTPException(status_code=401, detail="discord auth failed")
        me = discord_oauth.fetch_me(access)
        my_guilds = discord_oauth.fetch_me_guilds(access)
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=401, detail="discord auth failed") from exc

    discord_id = int(me["id"])
    display_name = me.get("global_name") or me.get("username") or f"discord:{discord_id}"
    avatar = (
        f"https://cdn.discordapp.com/avatars/{discord_id}/{me['avatar']}.png" if me.get("avatar") else None
    )
    with SessionLocal() as db:
        user = upsert_user(db, discord_id, display_name)
        user.avatar = avatar
        my_ids = {int(g["id"]) for g in my_guilds}
        known = {int(row[0]) for row in db.execute(text("SELECT id FROM guilds")).all()}
        shared = my_ids & known
        for guild_id in shared:
            upsert_membership(db, guild_id, discord_id)
        db.commit()
        guilds_out = [{"id": gid, "name": db.get(Guild, gid).name} for gid in sorted(shared)]
        token = issue_app_token(discord_id)
        return {
            "token": token,
            "user": {"id": user.id, "display_name": user.display_name, "avatar": user.avatar},
            "guilds": guilds_out,
        }


# ------------------------------------------------------------------ /app/me


@app_router.get("/me")
def me(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        user = db.get(User, user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="user not found")
        s = active_session(db, user_id)
        memberships = db.execute(
            text(
                """
                SELECT m.guild_id, g.name, m.visible
                FROM memberships m JOIN guilds g ON g.id = m.guild_id
                WHERE m.user_id = :u
                ORDER BY m.guild_id
                """
            ),
            {"u": user_id},
        ).all()
        session_out = None
        if s is not None:
            session_out = {
                "mood": s.mood,
                "activity": s.activity,
                "note": s.note,
                "source": s.source,  # 自分に対しては source を返してよい
                "started_at": s.started_at.isoformat(),
                "expires_at": s.expires_at.isoformat(),
                "remaining_minutes": domain._remaining_minutes(s.expires_at),
            }
        return {
            "user": {"id": user.id, "display_name": user.display_name, "avatar": user.avatar},
            "settings": {
                "notify_on_hima": user.notify_on_hima,
                "auto_mode": user.auto_mode,
                "auto_mood": user.auto_mood,
            },
            "session": session_out,
            "memberships": [
                {"guild_id": int(gid), "guild_name": name, "visible": visible}
                for gid, name, visible in memberships
            ],
        }


@app_router.put("/me/settings")
def update_settings(body: AppSettingsIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        user = db.get(User, user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="user not found")
        if body.notify_on_hima is not None:
            user.notify_on_hima = body.notify_on_hima
        if body.auto_mode is not None:
            user.auto_mode = body.auto_mode
        if body.auto_mood is not None:
            if body.auto_mood not in MOODS:
                raise HTTPException(status_code=400, detail="invalid mood")
            user.auto_mood = body.auto_mood
        db.commit()
        return {
            "notify_on_hima": user.notify_on_hima,
            "auto_mode": user.auto_mode,
            "auto_mood": user.auto_mood,
        }


@app_router.put("/memberships/{guild_id}/visibility")
def membership_visibility(guild_id: int, body: AppVisibilityIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        if db.get(Guild, guild_id) is None:
            raise HTTPException(status_code=404, detail="guild not found")
        m = upsert_membership(db, guild_id, user_id, visible=body.visible)
        db.commit()
        notify.update_counter_for_guild(db, guild_id, rest=discord_rest.rest)
        return {"guild_id": guild_id, "user_id": user_id, "visible": m.visible}


# ------------------------------------------------------------------ /app/board


@app_router.get("/board")
def board(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return domain.cross_guild_board(db, viewer_id=user_id)


# ------------------------------------------------------------------ /app/sessions


@app_router.post("/sessions")
def declare_session(body: AppSessionIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return domain.declare_session(
            db,
            user_id=user_id,
            mood=body.mood,
            activity=body.activity,
            note=body.note,
            minutes=body.minutes,
            source=body.source,
            rest=discord_rest.rest,
        )


@app_router.delete("/sessions")
def end_session(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return domain.end_session(db, user_id, rest=discord_rest.rest)


# ------------------------------------------------------------------ /app/knocks


@app_router.post("/knocks")
def create_knock(body: AppKnockIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return domain.create_knock(db, from_user=user_id, to_user=body.to_user, template=body.template)


@app_router.post("/knocks/{knock_id}/reply")
def knock_reply(knock_id: int, body: ReplyIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return domain.reply_knock(db, knock_id, user_id=user_id, action=body.action)


@app_router.post("/knocks/results/seen")
def knock_results_seen(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        marked = domain.mark_results_seen(db, user_id)
        return {"user_id": user_id, "marked": marked}


# ------------------------------------------------------------------ /app/blocks


@app_router.get("/blocks")
def list_blocks(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        rows = db.execute(
            text("SELECT blocked_id FROM blocks WHERE blocker_id = :u ORDER BY blocked_id"),
            {"u": user_id},
        ).scalars().all()
        return {"user_id": user_id, "blocked": [int(x) for x in rows]}


@app_router.post("/blocks")
def add_block(body: AppBlockIn, user_id: int = Depends(require_app_user)) -> dict:
    if user_id == body.blocked_user_id:
        raise HTTPException(status_code=400, detail="cannot block yourself")
    with SessionLocal() as db:
        row = db.get(Block, (user_id, body.blocked_user_id))
        if row is None:
            db.add(Block(blocker_id=user_id, blocked_id=body.blocked_user_id))
            db.commit()
        return {"user_id": user_id, "blocked_user_id": body.blocked_user_id, "blocked": True}


@app_router.delete("/blocks")
def remove_block(body: AppBlockIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        row = db.get(Block, (user_id, body.blocked_user_id))
        removed = row is not None
        if removed:
            db.delete(row)
            db.commit()
        return {"user_id": user_id, "blocked_user_id": body.blocked_user_id, "removed": removed}


# ------------------------------------------------------------------ /app/devices


@app_router.post("/devices")
def register_device(body: DeviceIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        device = db.get(Device, (user_id, body.fcm_token))
        if device is None:
            device = Device(user_id=user_id, fcm_token=body.fcm_token, platform=body.platform)
            db.add(device)
        else:
            device.platform = body.platform
        device.updated_at = utcnow()
        db.commit()
        return {"user_id": user_id, "fcm_token": body.fcm_token, "platform": device.platform}


@app_router.delete("/devices")
def delete_device(body: DeviceDeleteIn, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        device = db.get(Device, (user_id, body.fcm_token))
        removed = device is not None
        if removed:
            db.delete(device)
            db.commit()
        return {"user_id": user_id, "fcm_token": body.fcm_token, "removed": removed}
