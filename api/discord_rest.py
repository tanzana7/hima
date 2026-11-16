"""Thin Discord REST wrapper (Bot token, api v10). Never raises; callers just log.

Tests replace the module-level `rest` instance with a mock.
"""
from __future__ import annotations

import logging
from typing import Any

import httpx

from .config import settings

log = logging.getLogger("atsumaro.discord")


class DiscordRest:
    def __init__(
        self,
        token: str | None = None,
        base_url: str = "https://discord.com/api/v10",
        timeout: float = 10.0,
    ) -> None:
        self._fixed_token = token
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

    def _token(self) -> str:
        return self._fixed_token if self._fixed_token is not None else settings.discord_bot_token

    def _request(self, method: str, path: str, json_body: Any = None) -> Any:
        token = self._token()
        if not token:
            log.warning("discord: token not configured; skipped %s %s", method, path)
            return None
        try:
            with httpx.Client(timeout=self._timeout) as client:
                resp = client.request(
                    method,
                    self._base_url + path,
                    json=json_body,
                    headers={"Authorization": f"Bot {token}"},
                )
            if resp.status_code >= 400:
                log.warning(
                    "discord: %s %s -> HTTP %s %s", method, path, resp.status_code, resp.text[:200]
                )
                return None
            return resp.json() if resp.content else None
        except Exception as exc:  # noqa: BLE001 - callers only need None
            log.warning("discord: %s %s error: %s", method, path, exc)
            return None

    def open_dm_channel(self, user_id: int) -> str | None:
        """POST /users/@me/channels → DM channel id (None on failure)."""
        data = self._request("POST", "/users/@me/channels", {"recipient_id": int(user_id)})
        return data.get("id") if isinstance(data, dict) else None

    def send_message(
        self, channel_id: int | str, content: str, components: list | None = None
    ) -> dict | None:
        payload: dict[str, Any] = {"content": content}
        if components is not None:
            payload["components"] = components
        return self._request("POST", f"/channels/{channel_id}/messages", payload)

    def edit_message(self, channel_id: int | str, message_id: int | str, content: str) -> dict | None:
        return self._request(
            "PATCH", f"/channels/{channel_id}/messages/{message_id}", {"content": content}
        )

    def delete_message(self, channel_id: int | str, message_id: int | str) -> None:
        self._request("DELETE", f"/channels/{channel_id}/messages/{message_id}")


rest = DiscordRest()

PANEL_CONTENT = "Atsumaro パネル — 「今ヒマ！」で宣言、「やめる」で解除、掲示板で誰がいるか見られるよ！"
PANEL_CUSTOM_IDS = {"atsumaro:board", "atsumaro:join", "atsumaro:leave"}


def panel_components() -> list[dict]:
    """Button row for the shared panel message (custom_ids are part of the API contract)."""
    return [
        {
            "type": 1,
            "components": [
                {"type": 2, "style": 1, "label": "掲示板を見る", "custom_id": "atsumaro:board"},
                {"type": 2, "style": 3, "label": "今ヒマ！", "custom_id": "atsumaro:join"},
                {"type": 2, "style": 2, "label": "やめる", "custom_id": "atsumaro:leave"},
            ],
        }
    ]
