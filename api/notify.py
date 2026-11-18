"""Counter messages (debug count). Watch (お知らせ) notifications were removed 2026-11-18."""
from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

log = logging.getLogger("atsumaro.notify")


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
