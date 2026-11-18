"""App→API endpoints (all require the app JWT). The user id always comes from the JWT."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import text

from . import discord_oauth, discord_rest, domain, forecast
from .auth import issue_app_token, require_app_user
from .db import SessionLocal
from .models import Block, Device, Guild, Membership, RegularSlot, User
from .schemas import (
    AppBlockIn,
    AppKnockIn,
    AppReplyIn,
    AppSessionIn,
    AppSettingsIn,
    AppVisibilityIn,
    AuthIn,
    DeviceDeleteIn,
    DeviceIn,
    RegularSlotIn,
)
from .services import active_session, upsert_membership, upsert_user, utcnow, visible_guild_ids
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
        # 既存 membership の visible 変更のみ。新規作成は正規の経路（OAuth・Bot interaction）に限る
        m = db.get(Membership, (guild_id, user_id))
        if m is None:
            raise HTTPException(status_code=404, detail="membership not found")
        m.visible = body.visible
        db.commit()
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
def knock_reply(knock_id: int, body: AppReplyIn, user_id: int = Depends(require_app_user)) -> dict:
    """アプリ用返答。本人は JWT から取得し、ボディの user_id は受け取らない（信用しない）。"""
    with SessionLocal() as db:
        return domain.reply_knock(db, knock_id, user_id=user_id, action=body.action)


@app_router.get("/knocks/sent")
def knocks_sent(user_id: int = Depends(require_app_user)) -> dict:
    """自分が送ったお返事の履歴（新しい順）。"""
    with SessionLocal() as db:
        rows = db.execute(
            text(
                """
                SELECT k.id, k.to_user, k.template, k.status, k.created_at, k.responded_at,
                       u.display_name, u.avatar
                FROM knocks k
                LEFT JOIN users u ON u.id = k.to_user
                WHERE k.from_user = :u
                ORDER BY k.created_at DESC, k.id DESC
                """
            ),
            {"u": user_id},
        ).mappings().all()
        return {
            "user_id": user_id,
            "knocks": [
                {
                    "id": int(r["id"]),
                    "to_user": int(r["to_user"]),
                    "to_display_name": r["display_name"] or f"discord:{r['to_user']}",
                    "to_avatar": r["avatar"],
                    "template": r["template"],
                    "status": r["status"],
                    "created_at": r["created_at"].isoformat(),
                    "responded_at": r["responded_at"].isoformat() if r["responded_at"] else None,
                }
                for r in rows
            ],
        }


@app_router.post("/knocks/results/seen")
def knock_results_seen(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        marked = domain.mark_results_seen(db, user_id)
        return {"user_id": user_id, "marked": marked}


# ------------------------------------------------------------------ /app/members


@app_router.get("/members")
def list_members(guild_id: int | None = Query(None), user_id: int = Depends(require_app_user)) -> dict:
    """共有サーバーごとのメンバー一覧。

    guild_id 指定時はそのサーバーのメンバーのみ（本人が所属していなければ 404）。
    未指定時は本人が所属する全サーバーのメンバー。いずれも visible=true のメンバーを返す。
    """
    with SessionLocal() as db:
        if guild_id is not None:
            if db.get(Guild, guild_id) is None:
                raise HTTPException(status_code=404, detail="guild not found")
            if db.get(Membership, (guild_id, user_id)) is None:
                raise HTTPException(status_code=404, detail="not a member of this guild")
            guild_ids = [guild_id]
        else:
            guild_ids = visible_guild_ids(db, user_id)
            if not guild_ids:
                return {"user_id": user_id, "members": []}
        rows = db.execute(
            text(
                """
                SELECT m.guild_id, m.user_id, u.display_name, u.avatar
                FROM memberships m
                JOIN users u ON u.id = m.user_id
                WHERE m.guild_id = ANY(:gs) AND m.visible = true
                ORDER BY m.guild_id, m.user_id
                """
            ),
            {"gs": guild_ids},
        ).mappings().all()
        return {
            "user_id": user_id,
            "members": [
                {
                    "user_id": int(r["user_id"]),
                    "display_name": r["display_name"] or f"discord:{r['user_id']}",
                    "avatar": r["avatar"],
                    "guild_id": int(r["guild_id"]),
                }
                for r in rows
            ],
        }


# ------------------------------------------------------------------ /app/blocks


@app_router.get("/blocks")
def list_blocks(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        rows = db.execute(
            text(
                """
                SELECT b.blocked_id, u.display_name, u.avatar
                FROM blocks b
                LEFT JOIN users u ON u.id = b.blocked_id
                WHERE b.blocker_id = :u
                ORDER BY b.blocked_id
                """
            ),
            {"u": user_id},
        ).mappings().all()
        return {
            "user_id": user_id,
            "blocked": [int(r["blocked_id"]) for r in rows],
            "blocked_users": [
                {
                    "user_id": int(r["blocked_id"]),
                    "display_name": r["display_name"] or f"discord:{r['blocked_id']}",
                    "avatar": r["avatar"],
                }
                for r in rows
            ],
        }


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


# ------------------------------------------------------------------ /app/regular-slots


@app_router.get("/regular-slots")
def list_regular_slots(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        rows = (
            db.query(RegularSlot.id, RegularSlot.weekday, RegularSlot.start_min, RegularSlot.end_min)
            .filter(RegularSlot.user_id == user_id)
            .order_by(RegularSlot.weekday, RegularSlot.start_min)
            .all()
        )
        return {
            "user_id": user_id,
            "slots": [
                {"id": int(rid), "weekday": wd, "start_min": s, "end_min": e}
                for rid, wd, s, e in rows
            ],
        }


@app_router.post("/regular-slots")
def add_regular_slot(body: RegularSlotIn, user_id: int = Depends(require_app_user)) -> dict:
    if not 0 <= body.weekday <= 6:
        raise HTTPException(status_code=400, detail="invalid weekday (0=Mon..6=Sun)")
    if not (0 <= body.start_min <= 1439 and 0 <= body.end_min <= 1439):
        raise HTTPException(status_code=400, detail="invalid minutes (0..1439)")
    if body.start_min >= body.end_min:
        raise HTTPException(status_code=400, detail="start_min must be before end_min")
    with SessionLocal() as db:
        slot = RegularSlot(user_id=user_id, weekday=body.weekday,
                           start_min=body.start_min, end_min=body.end_min)
        db.add(slot)
        db.commit()
        return {"id": slot.id, "weekday": slot.weekday,
                "start_min": slot.start_min, "end_min": slot.end_min}


@app_router.delete("/regular-slots/{slot_id}")
def delete_regular_slot(slot_id: int, user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        slot = db.get(RegularSlot, slot_id)
        if slot is None or slot.user_id != user_id:
            raise HTTPException(status_code=404, detail="slot not found")
        db.delete(slot)
        db.commit()
        return {"user_id": user_id, "id": slot_id, "removed": True}


# ------------------------------------------------------------------ /app/free-time


@app_router.get("/free-time/forecast")
def free_time_forecast(user_id: int = Depends(require_app_user)) -> dict:
    with SessionLocal() as db:
        return {"user_id": user_id, "slots": forecast.compute_forecast(db, user_id)}
