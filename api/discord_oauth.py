"""Discord OAuth2 (authorization-code + PKCE) helpers. Tests patch these functions."""
from __future__ import annotations

import httpx
from fastapi import HTTPException

from .config import settings

TOKEN_URL = "https://discord.com/api/v10/oauth2/token"
ME_URL = "https://discord.com/api/v10/users/@me"
ME_GUILDS_URL = "https://discord.com/api/v10/users/@me/guilds"


def exchange_code(code: str, redirect_uri: str, code_verifier: str) -> dict:
    """Exchange an authorization code for tokens (PKCE). Returns the token payload."""
    try:
        resp = httpx.post(
            TOKEN_URL,
            data={
                "client_id": settings.discord_client_id,
                "client_secret": settings.discord_client_secret,
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri,
                "code_verifier": code_verifier,
            },
            timeout=10.0,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=401, detail="discord auth failed") from exc
    if resp.status_code >= 400:
        raise HTTPException(status_code=401, detail="discord auth failed")
    return resp.json()


def fetch_me(access_token: str) -> dict:
    try:
        resp = httpx.get(ME_URL, headers={"Authorization": f"Bearer {access_token}"}, timeout=10.0)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=401, detail="discord auth failed") from exc
    if resp.status_code >= 400:
        raise HTTPException(status_code=401, detail="discord auth failed")
    return resp.json()


def fetch_me_guilds(access_token: str) -> list:
    try:
        resp = httpx.get(ME_GUILDS_URL, headers={"Authorization": f"Bearer {access_token}"}, timeout=10.0)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=401, detail="discord auth failed") from exc
    if resp.status_code >= 400:
        raise HTTPException(status_code=401, detail="discord auth failed")
    return resp.json()
