"""Vocabulary shared with the Discord bot and the app. Contract source: docs/api-contract.md."""
from __future__ import annotations

# mood keys (fixed 2): ok=🙂 誘われ待ち / moon=🌙 ひっそり（fire は廃止。旧データは ok として扱う）
MOODS = {
    "ok": "🙂 誘われ待ち",
    "moon": "🌙 ひっそり（掲示板には出るが、マッチング通知は一切受けない）",
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

# hima_sessions.source: how the session was declared (Bot 側の宣言は常に manual)
HIMA_SOURCES = {"manual", "suggested", "auto"}

# matches.kind: role combination of the paired sessions (fire 廃止により ok_ok のみ)
MATCH_KINDS = {"ok_ok"}

# knocks.status lifecycle
KNOCK_STATUSES = {"sent", "accepted", "later", "passed", "expired"}

# knocks.template: fixed invitation phrases (keys follow the activity keys)
KNOCK_TEMPLATES = {
    "game": "ゲームしない？",
    "chat": "ちょっと話さない？",
    "work": "作業通話しない？",
}
