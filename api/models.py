"""SQLAlchemy 2.0 models. Discord IDs are BIGINT."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)  # Discord ID
    display_name: Mapped[str] = mapped_column(String(100))
    avatar: Mapped[str | None] = mapped_column(String(255))
    auto_mode: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    auto_mood: Mapped[str] = mapped_column(String(10), default="ok", server_default="ok")
    notify_on_hima: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class Guild(Base):
    __tablename__ = "guilds"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)  # Discord ID
    name: Mapped[str] = mapped_column(String(100))
    list_channel_id: Mapped[int | None] = mapped_column(BigInteger)  # 人数メッセージのチャンネル
    list_message_id: Mapped[int | None] = mapped_column(BigInteger)  # 旧方式（今後は書き込まない。掃除用に残す）
    panel_message_id: Mapped[int | None] = mapped_column(BigInteger)  # 旧方式（同上）
    base_topic: Mapped[str | None] = mapped_column(Text)  # 設置時のトピック（teardown で復元）
    topic_counter: Mapped[int | None] = mapped_column(Integer)  # トピックに描画済みの人数（変更時のみ PATCH）


class Membership(Base):
    __tablename__ = "memberships"

    guild_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("guilds.id"), primary_key=True
    )
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id"), primary_key=True
    )
    visible: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class HimaSession(Base):
    __tablename__ = "hima_sessions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"))
    mood: Mapped[str] = mapped_column(String(10))
    activity: Mapped[str] = mapped_column(String(20))
    note: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(20))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")  # デモ投入スクリプト由來

    __table_args__ = (
        Index(
            "uq_hima_sessions_active_user",
            "user_id",
            unique=True,
            postgresql_where=text("ended_at IS NULL"),
        ),
    )


class Block(Base):
    __tablename__ = "blocks"

    blocker_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    blocked_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Match(Base):
    __tablename__ = "matches"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    session_a_id: Mapped[int] = mapped_column(ForeignKey("hima_sessions.id"))
    session_b_id: Mapped[int] = mapped_column(ForeignKey("hima_sessions.id"))
    user_a: Mapped[int] = mapped_column(BigInteger)
    user_b: Mapped[int] = mapped_column(BigInteger)
    kind: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("session_a_id", "session_b_id", name="uq_matches_sessions"),
    )


class Knock(Base):
    __tablename__ = "knocks"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    from_user: Mapped[int] = mapped_column(BigInteger)
    to_user: Mapped[int] = mapped_column(BigInteger)
    template: Mapped[str | None] = mapped_column(String(50))  # None は「誘い文なし」
    status: Mapped[str] = mapped_column(String(20), default="sent", server_default="sent")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    responded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    result_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    dm_message_id: Mapped[int | None] = mapped_column(BigInteger)  # 着信 DM（🌙 宛は送らない）


class Device(Base):
    __tablename__ = "devices"

    user_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    fcm_token: Mapped[str] = mapped_column(String(255), primary_key=True)
    platform: Mapped[str] = mapped_column(String(20))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class RegularSlot(Base):
    __tablename__ = "regular_slots"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    user_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("users.id"))
    weekday: Mapped[int] = mapped_column(Integer)  # 0-6 (Mon=0)
    start_min: Mapped[int] = mapped_column(Integer)
    end_min: Mapped[int] = mapped_column(Integer)
    demo: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")  # デモ投入スクリプト由來


class SuggestionLog(Base):
    __tablename__ = "suggestion_log"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    user_id: Mapped[int] = mapped_column(BigInteger)
    slot_date: Mapped[datetime.date] = mapped_column(Date)  # 提案対象日のローカル日付
    weekday: Mapped[int] = mapped_column(Integer)  # 0-6 (Mon=0)
    start_min: Mapped[int] = mapped_column(Integer)
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "slot_date", "start_min", name="uq_suggestion_once_per_slot"),
    )


class WatchQueue(Base):
    __tablename__ = "watch_queue"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)  # BIGSERIAL
    watcher_id: Mapped[int] = mapped_column(BigInteger)
    session_id: Mapped[int] = mapped_column(ForeignKey("hima_sessions.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (
        Index(
            "ix_watch_queue_unsent",
            "watcher_id",
            postgresql_where=text("sent_at IS NULL"),
        ),
    )
