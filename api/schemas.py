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
    template: str | None = None


class ReplyIn(BaseModel):
    """Bot 用（共有シークレット認証・user_id 必須）。"""
    user_id: int
    action: str  # accept / later / pass


class AppReplyIn(BaseModel):
    """アプリ用（JWT 認証・本人は JWT から取得）。user_id は受け取らない。"""
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


class AppVisibilityIn(BaseModel):
    visible: bool


# --- app (JWT) ------------------------------------------------------------

class AuthIn(BaseModel):
    code: str
    redirect_uri: str
    code_verifier: str


class AppSessionIn(BaseModel):
    mood: str
    activity: str
    note: str | None = None
    minutes: int = 30
    source: str = "manual"


class AppSettingsIn(BaseModel):
    notify_on_hima: bool | None = None
    auto_mode: bool | None = None
    auto_mood: str | None = None


class AppKnockIn(BaseModel):
    to_user: int
    template: str | None = None


class AppBlockIn(BaseModel):
    blocked_user_id: int


class DeviceIn(BaseModel):
    platform: str
    fcm_token: str


class DeviceDeleteIn(BaseModel):
    fcm_token: str


class RegularSlotIn(BaseModel):
    weekday: int
    start_min: int
    end_min: int


class SuggestDeclareIn(BaseModel):
    user_id: int
