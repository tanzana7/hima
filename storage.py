"""SQLite storage for hima-bot (standard library sqlite3 only)."""
from __future__ import annotations

import sqlite3
from typing import Iterable, Optional

DB_PATH = "data.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS guild_config (
    guild_id         INTEGER PRIMARY KEY,
    channel_id       INTEGER NOT NULL,
    panel_message_id INTEGER NOT NULL,
    list_message_id  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS hima_status (
    guild_id     INTEGER NOT NULL,
    user_id      INTEGER NOT NULL,
    display_name TEXT    NOT NULL,
    started_at   INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    mood         TEXT    NOT NULL,
    activity     TEXT    NOT NULL,
    note         TEXT    NOT NULL DEFAULT '',
    announce_message_id INTEGER,
    PRIMARY KEY (guild_id, user_id)
);

CREATE TABLE IF NOT EXISTS knock_log (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id     INTEGER NOT NULL,
    from_user_id INTEGER NOT NULL,
    to_user_id   INTEGER NOT NULL,
    template     TEXT    NOT NULL,
    status       TEXT    NOT NULL,
    created_at   INTEGER NOT NULL,
    dm_message_id INTEGER,
    result_seen  INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_hima_expires ON hima_status (expires_at);
CREATE INDEX IF NOT EXISTS idx_knock_pair ON knock_log (guild_id, from_user_id, to_user_id, created_at);
"""

_conn: Optional[sqlite3.Connection] = None


def init(db_path: str = DB_PATH) -> None:
    """Open (or create) the database, migrate missing columns and keep existing data."""
    global _conn
    _conn = sqlite3.connect(db_path)
    _conn.row_factory = sqlite3.Row
    _conn.executescript(SCHEMA)
    # Migrations: add columns only when missing; existing data is preserved.
    _ensure_column("hima_status", "announce_message_id", "INTEGER")
    _ensure_column("knock_log", "dm_message_id", "INTEGER")
    _ensure_column("knock_log", "result_seen", "INTEGER NOT NULL DEFAULT 0")
    _conn.commit()


def _ensure_column(table: str, column: str, decl: str) -> None:
    assert _conn is not None
    columns = {row[1] for row in _conn.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in columns:
        _conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {decl}")


def _c() -> sqlite3.Connection:
    if _conn is None:
        init()
    assert _conn is not None
    return _conn


# ---------------------------------------------------------------- guild_config


def get_guild_config(guild_id: int) -> Optional[sqlite3.Row]:
    cur = _c().execute("SELECT * FROM guild_config WHERE guild_id = ?", (guild_id,))
    return cur.fetchone()


def set_guild_config(guild_id: int, channel_id: int, panel_message_id: int, list_message_id: int) -> None:
    _c().execute(
        """
        INSERT INTO guild_config (guild_id, channel_id, panel_message_id, list_message_id)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (guild_id) DO UPDATE SET
            channel_id = excluded.channel_id,
            panel_message_id = excluded.panel_message_id,
            list_message_id = excluded.list_message_id
        """,
        (guild_id, channel_id, panel_message_id, list_message_id),
    )
    _c().commit()


def delete_guild_config(guild_id: int) -> bool:
    """Remove the public panel config for a guild. Returns True when a row was deleted."""
    cur = _c().execute("DELETE FROM guild_config WHERE guild_id = ?", (guild_id,))
    _c().commit()
    return cur.rowcount > 0


# ----------------------------------------------------------------- hima_status


def upsert_hima(
    guild_id: int,
    user_id: int,
    display_name: str,
    started_at: int,
    expires_at: int,
    mood: str,
    activity: str,
    note: str,
    announce_message_id: Optional[int] = None,
) -> None:
    """Insert or overwrite (extend) the user's hima registration."""
    _c().execute(
        """
        INSERT INTO hima_status
            (guild_id, user_id, display_name, started_at, expires_at, mood, activity, note, announce_message_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (guild_id, user_id) DO UPDATE SET
            display_name = excluded.display_name,
            started_at = excluded.started_at,
            expires_at = excluded.expires_at,
            mood = excluded.mood,
            activity = excluded.activity,
            note = excluded.note,
            announce_message_id = excluded.announce_message_id
        """,
        (guild_id, user_id, display_name, started_at, expires_at, mood, activity, note, announce_message_id),
    )
    _c().commit()


def set_announce_message_id(guild_id: int, user_id: int, message_id: Optional[int]) -> None:
    """Store (or clear) the announcement message id of a registration."""
    _c().execute(
        "UPDATE hima_status SET announce_message_id = ? WHERE guild_id = ? AND user_id = ?",
        (message_id, guild_id, user_id),
    )
    _c().commit()


def get_hima(guild_id: int, user_id: int) -> Optional[sqlite3.Row]:
    cur = _c().execute(
        "SELECT * FROM hima_status WHERE guild_id = ? AND user_id = ?", (guild_id, user_id)
    )
    return cur.fetchone()


def delete_hima(guild_id: int, user_id: int) -> bool:
    """Remove the user's registration. Returns True when a row was deleted."""
    cur = _c().execute(
        "DELETE FROM hima_status WHERE guild_id = ? AND user_id = ?", (guild_id, user_id)
    )
    _c().commit()
    return cur.rowcount > 0


def list_hima(guild_id: int, now: int) -> Iterable[sqlite3.Row]:
    """Currently valid registrations for a guild, soonest-expiring first."""
    cur = _c().execute(
        """
        SELECT * FROM hima_status
        WHERE guild_id = ? AND expires_at > ?
        ORDER BY expires_at ASC
        """,
        (guild_id, now),
    )
    return cur.fetchall()


def purge_expired(now: int) -> Iterable[sqlite3.Row]:
    """Delete expired registrations and return the deleted rows (for cleanup)."""
    cur = _c().execute("SELECT * FROM hima_status WHERE expires_at <= ?", (now,))
    rows = cur.fetchall()
    if rows:
        _c().execute("DELETE FROM hima_status WHERE expires_at <= ?", (now,))
        _c().commit()
    return rows


# ------------------------------------------------------------------ knock_log


def record_knock(
    guild_id: int,
    from_user_id: int,
    to_user_id: int,
    template: str,
    status: str,
    created_at: int,
    dm_message_id: Optional[int] = None,
) -> int:
    """Insert a knock row and return its id."""
    cur = _c().execute(
        """
        INSERT INTO knock_log (guild_id, from_user_id, to_user_id, template, status, created_at, dm_message_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (guild_id, from_user_id, to_user_id, template, status, created_at, dm_message_id),
    )
    _c().commit()
    return int(cur.lastrowid)


def update_knock_dm(knock_id: int, dm_message_id: int) -> None:
    """Store the DM message id of a sent knock."""
    _c().execute("UPDATE knock_log SET dm_message_id = ? WHERE id = ?", (dm_message_id, knock_id))
    _c().commit()


def list_unanswered_knocks() -> Iterable[sqlite3.Row]:
    """Knocks still awaiting a reply (inbox delivery; dm_message_id is unused now)."""
    cur = _c().execute("SELECT * FROM knock_log WHERE status = 'sent'")
    return cur.fetchall()


def list_knocks_inbox(guild_id: int, user_id: int, limit: int = 5) -> Iterable[sqlite3.Row]:
    """Unanswered knocks addressed to the user, newest first."""
    cur = _c().execute(
        """
        SELECT * FROM knock_log
        WHERE guild_id = ? AND to_user_id = ? AND status = 'sent'
        ORDER BY created_at DESC
        LIMIT ?
        """,
        (guild_id, user_id, limit),
    )
    return cur.fetchall()


def list_knock_results(guild_id: int, user_id: int) -> Iterable[sqlite3.Row]:
    """Knocks the user sent that got a reply but are not seen yet."""
    cur = _c().execute(
        """
        SELECT * FROM knock_log
        WHERE guild_id = ? AND from_user_id = ? AND status != 'sent' AND result_seen = 0
        ORDER BY created_at DESC
        """,
        (guild_id, user_id),
    )
    return cur.fetchall()


def mark_results_seen(knock_ids: Iterable[int]) -> None:
    """Mark the given knock rows as seen in the results pane."""
    ids = list(knock_ids)
    if not ids:
        return
    placeholders = ",".join("?" for _ in ids)
    _c().execute(
        f"UPDATE knock_log SET result_seen = 1 WHERE id IN ({placeholders})", ids
    )
    _c().commit()


def get_knock(knock_id: int) -> Optional[sqlite3.Row]:
    cur = _c().execute("SELECT * FROM knock_log WHERE id = ?", (knock_id,))
    return cur.fetchone()


def update_knock_status(knock_id: int, status: str) -> None:
    _c().execute("UPDATE knock_log SET status = ? WHERE id = ?", (status, knock_id))
    _c().commit()


def recent_knock_exists(guild_id: int, user_a: int, user_b: int, now: int, window: int = 300) -> bool:
    """True when the same pair knocked within `window` seconds (both directions)."""
    cur = _c().execute(
        """
        SELECT 1 FROM knock_log
        WHERE guild_id = ?
          AND created_at > ?
          AND (
                (from_user_id = ? AND to_user_id = ?)
             OR (from_user_id = ? AND to_user_id = ?)
              )
        LIMIT 1
        """,
        (guild_id, now - window, user_a, user_b, user_b, user_a),
    )
    return cur.fetchone() is not None
