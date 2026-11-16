"""Request bodies for the Bot→API endpoints."""
from __future__ import annotations

from pydantic import BaseModel


class SetupIn(BaseModel):
    name: str
    channel_id: int


class SessionIn(BaseModel):
    user_id: int
    display_name: str
    guild_id: int
    mood: str
    activity: str
    note: str | None = None
    minutes: int = 30


class EndSessionIn(BaseModel):
    user_id: int


class ResultsSeenIn(BaseModel):
    user_id: int


class KnockIn(BaseModel):
    from_user: int
    to_user: int
    template: str


class ReplyIn(BaseModel):
    user_id: int
    action: str  # accept / later / pass


class BlockIn(BaseModel):
    user_id: int
    blocked_user_id: int


class SettingsIn(BaseModel):
    notify_on_hima: bool


class VisibilityIn(BaseModel):
    user_id: int
    guild_id: int
    visible: bool
