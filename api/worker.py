"""In-process background worker (30s tick, advisory-locked)."""
from __future__ import annotations

import logging
import threading

from sqlalchemy import text

from . import notify, suggestions
from .db import SessionLocal, engine

log = logging.getLogger("atsumaro.worker")

TICK_SECONDS = 30
ADVISORY_LOCK_KEY = 81140501  # arbitrary fixed key for "atsumaro api worker"


def _close_expired_sessions() -> int:
    """Close sessions whose expires_at passed and which are still open."""
    with SessionLocal() as session:
        result = session.execute(
            text(
                """
                UPDATE hima_sessions
                SET ended_at = now()
                WHERE ended_at IS NULL AND expires_at <= now()
                """
            )
        )
        session.commit()
        return result.rowcount or 0


def run_tick(rest=None) -> int:
    """One unit of periodic work: close expired sessions then refresh counters."""
    closed = _close_expired_sessions()
    notify.refresh_all_counters(rest=rest)
    return closed


def _run(stop_event: threading.Event) -> None:
    conn = engine.connect()
    try:
        acquired = conn.execute(
            text("SELECT pg_try_advisory_lock(:key)"), {"key": ADVISORY_LOCK_KEY}
        ).scalar()
        if not acquired:
            log.info("advisory lock not acquired; another worker is active")
            return
        log.info("worker started (advisory lock acquired)")
        ticks = 0
        while not stop_event.wait(TICK_SECONDS):
            try:
                closed = run_tick()
                if closed:
                    log.info("worker closed %d expired session(s)", closed)
                ticks += 1
                if ticks % notify.FLUSH_INTERVAL_TICKS == 0:
                    notified = notify.flush_watch_queue()
                    if notified:
                        log.info("watch flush notified %d watcher(s)", notified)
                if ticks % suggestions.SUGGEST_EVERY_TICKS == 0:
                    with SessionLocal() as session:
                        sent = suggestions.suggestion_pass(session)
                        if sent:
                            log.info("suggestions sent to %d user(s)", sent)
            except Exception:  # noqa: BLE001 - the worker must survive tick errors
                log.exception("worker tick failed")
    finally:
        try:
            conn.execute(text("SELECT pg_advisory_unlock(:key)"), {"key": ADVISORY_LOCK_KEY})
        except Exception:  # noqa: BLE001
            pass
        conn.close()


def start_worker(stop_event: threading.Event) -> threading.Thread | None:
    """Spawn the worker thread. The advisory lock is checked inside the thread."""
    thread = threading.Thread(target=_run, args=(stop_event,), name="atsumaro-worker", daemon=True)
    thread.start()
    return thread
