"""Async HTTP client for the Atsumaro API (Bot credentials).

Raises ApiConnectionError / ApiHTTPError; callers turn them into friendly
ephemeral messages instead of crashing.
"""
from __future__ import annotations

import os

import httpx

DEFAULT_BASE_URL = "http://127.0.0.1:8000"


class ApiError(Exception):
    pass


class ApiConnectionError(ApiError):
    """Could not reach the API server at all."""


class ApiHTTPError(ApiError):
    """The API server answered with an error status."""

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(f"HTTP {status_code}: {detail}")
        self.status_code = status_code
        self.detail = detail


class ApiClient:
    def __init__(self, base_url: str | None = None, secret: str | None = None) -> None:
        self.base_url = (base_url or os.getenv("API_BASE_URL") or DEFAULT_BASE_URL).rstrip("/")
        self.secret = secret if secret is not None else (os.getenv("BOT_API_SECRET") or "")

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.secret}"}

    async def _request(self, method: str, path: str, *, json_body=None, params=None):
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.request(
                    method,
                    self.base_url + path,
                    json=json_body,
                    params=params,
                    headers=self._headers(),
                )
        except httpx.HTTPError as exc:  # network / timeout / DNS
            raise ApiConnectionError(str(exc)) from exc
        if resp.status_code >= 400:
            try:
                detail = resp.json().get("detail", resp.text)
            except Exception:  # noqa: BLE001
                detail = resp.text
            raise ApiHTTPError(resp.status_code, str(detail))
        return resp.json() if resp.content else None

    # --- guild panel -------------------------------------------------
    async def setup_guild(self, guild_id: int, name: str, channel_id: int | None = None) -> dict:
        body: dict = {"name": name}
        if channel_id is not None:
            body["channel_id"] = channel_id
        return await self._request("POST", f"/bot/guilds/{guild_id}/setup", json_body=body)

    async def teardown_guild(self, guild_id: int) -> dict:
        return await self._request("POST", f"/bot/guilds/{guild_id}/teardown")

    # --- sessions ----------------------------------------------------
    async def declare_session(
        self, *, user_id: int, display_name: str, guild_id: int, guild_name: str | None,
        mood: str, activity: str, note: str | None, minutes: int,
    ) -> dict:
        return await self._request(
            "POST",
            "/bot/sessions",
            json_body={
                "user_id": user_id,
                "display_name": display_name,
                "guild_id": guild_id,
                "guild_name": guild_name,
                "mood": mood,
                "activity": activity,
                "note": note,
                "minutes": minutes,
            },
        )

    async def end_session(self, user_id: int) -> dict:
        return await self._request("DELETE", "/bot/sessions", json_body={"user_id": user_id})

    async def suggest_declare(self, user_id: int) -> dict:
        """提案 DM の「このまま宣言する」（source=suggested / 30分 / auto_mood）。"""
        return await self._request("POST", "/bot/suggest-declare", json_body={"user_id": user_id})

    async def get_board(
        self, guild_id: int, user_id: int, display_name: str | None = None, guild_name: str | None = None
    ) -> dict:
        params: dict = {"guild_id": guild_id, "user_id": user_id}
        if display_name is not None:
            params["display_name"] = display_name
        if guild_name is not None:
            params["guild_name"] = guild_name
        return await self._request("GET", "/bot/board", params=params)

    # --- knocks ------------------------------------------------------
    async def results_seen(self, user_id: int) -> dict:
        return await self._request("POST", "/bot/knocks/results/seen", json_body={"user_id": user_id})

    async def create_knock(self, *, from_user: int, to_user: int, template: str | None, display_name: str | None = None) -> dict:
        body: dict = {"from_user": from_user, "to_user": to_user, "template": template}
        if display_name is not None:
            body["display_name"] = display_name
        return await self._request("POST", "/bot/knocks", json_body=body)

    async def reply_knock(self, knock_id: int, *, user_id: int, action: str) -> dict:
        return await self._request(
            "POST", f"/bot/knocks/{knock_id}/reply", json_body={"user_id": user_id, "action": action}
        )

    # --- blocks ------------------------------------------------------
    async def add_block(self, user_id: int, blocked_user_id: int) -> dict:
        return await self._request(
            "POST", "/bot/blocks", json_body={"user_id": user_id, "blocked_user_id": blocked_user_id}
        )

    async def remove_block(self, user_id: int, blocked_user_id: int) -> dict:
        return await self._request(
            "DELETE", "/bot/blocks", json_body={"user_id": user_id, "blocked_user_id": blocked_user_id}
        )

    async def list_blocks(self, user_id: int) -> dict:
        return await self._request("GET", "/bot/blocks", params={"user_id": user_id})

    # --- users / memberships ----------------------------------------
    async def update_settings(self, user_id: int, *, notify_on_hima: bool, display_name: str | None = None) -> dict:
        body: dict = {"notify_on_hima": notify_on_hima}
        if display_name is not None:
            body["display_name"] = display_name
        return await self._request("PUT", f"/bot/users/{user_id}/settings", json_body=body)

    async def update_visibility(self, user_id: int, guild_id: int, *, visible: bool, display_name: str | None = None, guild_name: str | None = None) -> dict:
        body: dict = {"user_id": user_id, "guild_id": guild_id, "visible": visible}
        if display_name is not None:
            body["display_name"] = display_name
        if guild_name is not None:
            body["guild_name"] = guild_name
        return await self._request("PUT", "/bot/memberships/visibility", json_body=body)
