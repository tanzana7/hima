"""Atsumaro API — foundation (business endpoints come in the next stage)."""
from __future__ import annotations

import logging
import threading
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from sqlalchemy import text

from . import worker
from .auth import require_bot_secret
from .db import engine
from .routes_bot import router as bot_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("atsumaro")

_stop_event = threading.Event()
_worker_thread: threading.Thread | None = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global _worker_thread
    _stop = threading.Event()
    _worker_thread = worker.start_worker(_stop)
    yield
    _stop.set()
    if _worker_thread is not None:
        _worker_thread.join(timeout=5)


app = FastAPI(title="Atsumaro API", version="0.2.0", lifespan=lifespan)
app.include_router(bot_router)


@app.get("/health")
def health() -> dict:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    return {"status": "ok", "db": "up"}


@app.get("/bot/ping")
def bot_ping(_: None = Depends(require_bot_secret)) -> dict:
    """Sample Bot→API endpoint proving the bearer-secret dependency works."""
    return {"ok": True}
