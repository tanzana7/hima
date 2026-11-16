"""Domain helpers (skeleton)."""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session


def is_blocked(session: Session, user_a: int, user_b: int) -> bool:
    """True when a block row exists in either direction between the two users."""
    row = session.execute(
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
