"""Shared data helpers (users, memberships, visibility, blocks)."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from .models import HimaSession, Membership, User


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def upsert_user(db: Session, user_id: int, display_name: str | None = None) -> User:
    user = db.get(User, user_id)
    if user is None:
        user = User(id=user_id, display_name=display_name or f"discord:{user_id}")
        db.add(user)
        db.flush()
    elif display_name:
        user.display_name = display_name
    return user


def upsert_membership(db: Session, guild_id: int, user_id: int, visible: bool | None = None) -> Membership:
    m = db.get(Membership, (guild_id, user_id))
    if m is None:
        m = Membership(guild_id=guild_id, user_id=user_id, visible=True if visible is None else visible)
        db.add(m)
        db.flush()
    else:
        m.last_seen_at = utcnow()
        if visible is not None:
            m.visible = visible
    return m


def active_session(db: Session, user_id: int) -> HimaSession | None:
    return (
        db.query(HimaSession)
        .filter(HimaSession.user_id == user_id, HimaSession.ended_at.is_(None))
        .first()
    )


def has_shared_visible_guild(db: Session, user_a: int, user_b: int) -> bool:
    row = db.execute(
        text(
            """
            SELECT 1
            FROM memberships m1
            JOIN memberships m2
              ON m2.guild_id = m1.guild_id AND m2.visible = true AND m2.user_id = :b
            WHERE m1.user_id = :a AND m1.visible = true
            LIMIT 1
            """
        ),
        {"a": user_a, "b": user_b},
    ).first()
    return row is not None


def visible_guild_ids(db: Session, user_id: int) -> list[int]:
    rows = db.execute(
        text("SELECT guild_id FROM memberships WHERE user_id = :u AND visible = true"),
        {"u": user_id},
    ).scalars().all()
    return [int(g) for g in rows]


def blocked_ids(db: Session, user_id: int) -> set[int]:
    rows = db.execute(
        text(
            """
            SELECT CASE WHEN blocker_id = :u THEN blocked_id ELSE blocker_id END AS other
            FROM blocks
            WHERE blocker_id = :u OR blocked_id = :u
            """
        ),
        {"u": user_id},
    ).scalars().all()
    return {int(x) for x in rows}


def is_blocked(db: Session, user_a: int, user_b: int) -> bool:
    """True when a block row exists in either direction between the two users."""
    row = db.execute(
        text(
            """
            SELECT 1 FROM blocks
            WHERE (blocker_id = :a AND blocked_id = :b)
               OR (blocker_id = :b AND blocked_id = :a)
            LIMIT 1
            """
        ),
        {"a": user_a, "b": user_b},
    ).first()
    return row is not None
