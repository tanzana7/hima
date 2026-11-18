"""Shared domain operations used by both the Bot and App routes (single implementation)."""
from __future__ import annotations

import logging
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import text

from . import matching
from . import discord_rest as _discord_rest
from .discord_rest import knock_reply_components
from .db import SessionLocal
from .models import Guild, HimaSession, Knock, Membership, User
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

log = logging.getLogger("atsumaro.domain")

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
    """宣言（新規 or 延長）。マッチング評価・見守りキュー登録も行う。"""
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
    # お知らせ（watch）通知は廃止。暇宣言は誰にも通知がいかない（見たい人が掲示板で確認する）
    return {"session_id": row.id, "created": created, "expires_at": row.expires_at.isoformat()}


def end_session(db, user_id: int, rest=None) -> dict:
    """有効セッション終了。宛ノックを expired にし（着信 DM も削除）する。"""
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
    cleanup_knock_dms([user_id], rest=rest)
    return {"user_id": user_id, "ended": ended}


def create_knock(db, *, from_user: int, to_user: int, template: str | None, display_name: str | None = None, rest=None) -> dict:
    if from_user == to_user:
        raise HTTPException(status_code=400, detail="cannot knock yourself")
    # 送信者の users 行を本物の表示名で upsert（着信 DM・受信箱の名前が仮名にならないように）
    upsert_user(db, from_user, display_name)
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
    _send_knock_dm(db, knock, sender_name, template, rest)
    push_body = f"{sender_name} さんが「{template}」" if template else f"{sender_name} さんから"
    send_push(db, to_user, "🔔 お返事が届いたよ！", push_body)
    return {"id": knock.id, "from_user": knock.from_user, "to_user": knock.to_user, "status": knock.status}


MOOD_EMOJI = {"fire": "🔥", "ok": "🙂", "moon": "🌙"}


def _send_knock_dm(db, knock, sender_name: str, template: str, rest=None) -> None:
    """ノック着信 DM（🌙 宛は送らない）。失敗はログのみでノック作成自体は成功。"""
    rest = rest or _discord_rest.rest
    if rest is None:
        return
    try:
        receiver_session = active_session(db, knock.to_user)
        if receiver_session is None or receiver_session.mood == "moon":
            return  # 🌙 は通知を受けない役割（受信箱で見る）
        channel = rest.open_dm_channel(knock.to_user)
        if channel is None:
            return
        if template:
            lines = [f"{sender_name} さんからお返事が届いたよ：「{template}」"]
        else:
            lines = [f"{sender_name} さんからお返事が届いたよ"]
        sender_session = active_session(db, knock.from_user)
        if sender_session is not None:
            remaining = max(0, int((sender_session.expires_at - utcnow()).total_seconds() // 60))
            lines.append(
                f"{sender_name} さんは今 {MOOD_EMOJI.get(sender_session.mood, '')} "
                f"{ACTIVITIES.get(sender_session.activity, sender_session.activity)} 中・あと{remaining}分"
            )
        msg = rest.send_message(channel, "\n".join(lines), components=knock_reply_components(knock.id))
        if isinstance(msg, dict) and msg.get("id"):
            knock.dm_message_id = int(msg["id"])
            db.commit()
    except Exception:  # noqa: BLE001 - DM 失敗でもノック作成は成功扱い
        log.exception("knock arrival DM failed knock_id=%s (ignored)", knock.id)


def cleanup_knock_dms(user_ids: list[int] | None = None, rest=None) -> int:
    """期限切れになったノックの着信 DM を削除する（チャンネルは宛先との DM を開き直して特定）。

    user_ids を指定すれば宛先を限定する。None なら全ての「expired かつ DM 未削除」を対象にする。
    """
    rest = rest or _discord_rest.rest
    if user_ids is not None and not user_ids:
        return 0
    deleted = 0
    with SessionLocal() as db:
        if user_ids is not None:
            rows = db.execute(
                text(
                    """
                    SELECT id, to_user, dm_message_id
                    FROM knocks
                    WHERE status = 'expired' AND dm_message_id IS NOT NULL AND to_user = ANY(:ids)
                    """
                ),
                {"ids": user_ids},
            ).mappings().all()
        else:
            rows = db.execute(
                text(
                    """
                    SELECT id, to_user, dm_message_id
                    FROM knocks
                    WHERE status = 'expired' AND dm_message_id IS NOT NULL
                    """
                )
            ).mappings().all()
        for r in rows:
            channel = rest.open_dm_channel(int(r["to_user"]))
            if channel is not None:
                rest.delete_message(channel, int(r["dm_message_id"]))
            # 削除の成否にかかわらずフラグを落とす（tick ごとの再試行を防ぐ）
            db.execute(text("UPDATE knocks SET dm_message_id = NULL WHERE id = :i"), {"i": r["id"]})
            deleted += 1
        db.commit()
    return deleted


def expire_knocks_and_cleanup_dms(user_ids: list[int], rest=None) -> int:
    """セッションが消えた当事者の未返答ノックを expired にし、着信 DM を削除する（ワーカー用）。"""
    with SessionLocal() as db:
        db.execute(
            text(
                """
                UPDATE knocks SET status = 'expired'
                WHERE status = 'sent' AND (to_user = ANY(:ids) OR from_user = ANY(:ids))
                """
            ),
            {"ids": user_ids},
        )
        db.commit()
    return cleanup_knock_dms(None, rest=rest)


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
    if knock.status == "accepted":
        # 「いいよ！」のときだけ送信者へ DM 1通（あとで/パスは結果欄のみ。🌙 宛抑制とは扱いを分けて送る）
        _notify_sender_accepted(db, knock, receiver_name, rest)
    return {"id": knock.id, "status": knock.status, "responded_at": knock.responded_at.isoformat()}


def _notify_sender_accepted(db, knock, receiver_name: str, rest=None) -> None:
    """accepted 返答時に送信者へ DM 1通（ボタンなし・通知のみ）。

    DM 送信に失敗しても返答処理自体は成功扱い（着信 DM と同じ方針・ログのみ）。
    送信者が 🌙 のセッションを持っていても送る（自分の送ったお返事への反応のため）。
    """
    rest = rest or _discord_rest.rest
    if rest is None:
        return
    try:
        channel = rest.open_dm_channel(knock.from_user)
        if channel is None:
            return
        rest.send_message(channel, f"{receiver_name} さんがお返事に『いいよ！』してくれたよ")
    except Exception:  # noqa: BLE001 - DM 失敗でも返答記録は有効
        log.exception("accepted notification DM failed knock_id=%s (ignored)", knock.id)


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
                "from_avatar": sender.avatar if sender else None,
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


def board_for_guild(db, *, guild_id: int, viewer_id: int, display_name: str | None = None) -> dict:
    """単一ギルドの掲示板（Bot 向け）。共有可視・ブロック除外・source 非表示。"""
    # 契約（§2）: guild_id と user_id を含む Bot リクエストは membership を upsertする。
    # 掲示板を見ただけのユーザーも membership が作られ、「お返事」が送れるようになる。
    # 既存行の visible は上書きしない（非表示設定を尊重。last_seen_at のみ更新）。
    # users の display_name は Bot が渡した本物の表示名で更新する（仮名・空値では上書きしない）。
    if db.get(Guild, guild_id) is not None:  # 未登録ギルドは FK のため作れない（board 自体は参照可）
        upsert_user(db, viewer_id, display_name)
        upsert_membership(db, guild_id, viewer_id)
        db.commit()
    viewer_active = active_session(db, viewer_id)
    viewer_mood = viewer_active.mood if viewer_active else None
    hidden = blocked_ids(db, viewer_id)

    rows = db.execute(
        text(
            """
            SELECT s.user_id, u.display_name, u.avatar, s.mood, s.activity, s.note, s.expires_at
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
                "avatar": r["avatar"],
                "mood": r["mood"],
                "activity": r["activity"],
                "note": r["note"],
                "remaining_minutes": _remaining_minutes(r["expires_at"]),
                "expires_at": r["expires_at"].isoformat(),
            }
        )

    inbox, results = _inbox_and_results(db, viewer_id, viewer_mood)
    viewer = db.get(User, viewer_id)
    if viewer is None:
        # 初めて board を開いたユーザーも作る（notify_on_hima はデフォルト ON に従う）
        viewer = upsert_user(db, viewer_id, display_name)
        db.commit()
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
            SELECT s.user_id, u.display_name, u.avatar, s.mood, s.activity, s.note, s.expires_at
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
                "avatar": r["avatar"],
                "mood": r["mood"],
                "activity": r["activity"],
                "note": r["note"],
                "remaining_minutes": _remaining_minutes(r["expires_at"]),
                "expires_at": r["expires_at"].isoformat(),
                "shared_guild_ids": shared,
            }
        )

    inbox, results = _inbox_and_results(db, viewer_id, viewer_mood)
    if db.get(User, viewer_id) is None:
        # 初めて board を開いたユーザーも作る（notify_on_hima はデフォルト ON に従う）
        upsert_user(db, viewer_id)
        db.commit()
    return {"viewer_id": viewer_id, "sessions": sessions_out, "inbox": inbox, "results": results}
