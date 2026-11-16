"""Vocabulary shared with the Discord bot and the app. Contract source: docs/api-contract.md."""
from __future__ import annotations

# mood keys (fixed 3): fire=🔥 誘う人 / ok=🙂 誘われ待ち / moon=🌙 静か
MOODS = {
    "fire": "🔥 誘う人（自分から誘う）",
    "ok": "🙂 誘われ待ち",
    "moon": "🌙 静か（掲示板には出るが、マッチング通知は一切受けない）",
}
DEFAULT_MOOD = "ok"

# activity keys (inherited from the existing bot)
ACTIVITIES = {
    "game": "🎮 ゲーム",
    "chat": "💬 雑談・通話",
    "work": "💻 作業通話",
    "out": "🚶 外出",
    "any": "✨ なんでもOK",
}

# hima_sessions.source: how the session was declared
HIMA_SOURCES = {"panel", "command", "app", "auto"}

# matches.kind: role combination of the paired sessions
MATCH_KINDS = {"fire_fire", "fire_ok", "ok_ok"}

# knocks.status lifecycle
KNOCK_STATUSES = {"sent", "accepted", "later", "passed", "expired"}

# knocks.template: fixed invitation phrases (keys follow the activity keys)
KNOCK_TEMPLATES = {
    "game": "ゲームしない？",
    "chat": "ちょっと話さない？",
    "work": "作業通話しない？",
}
