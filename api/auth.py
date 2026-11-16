"""Auth skeleton: Bot→API secret bearer + App→API JWT (HS256, 30 days)."""
from __future__ import annotations

import time

import jwt
from fastapi import Header, HTTPException

from .config import settings

JWT_ALGORITHM = "HS256"
JWT_TTL_SECONDS = 30 * 24 * 3600  # 30 days


def require_bot_secret(authorization: str = Header(...)) -> None:
    """Bot→API: validate `Authorization: Bearer <BOT_API_SECRET>`.

    Only requests passing this check may trust a user ID passed in body/headers.
    """
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="invalid bot secret")
    if authorization[len("Bearer ") :] != settings.bot_api_secret:
        raise HTTPException(status_code=401, detail="invalid bot secret")


def issue_app_token(user_id: int) -> str:
    """App→API: issue a session token (HS256, 30 days). OAuth exchange comes later."""
    now = int(time.time())
    payload = {"sub": str(user_id), "iat": now, "exp": now + JWT_TTL_SECONDS}
    return jwt.encode(payload, settings.api_jwt_secret, algorithm=JWT_ALGORITHM)


def verify_app_token(token: str) -> int:
    """Validate an app token and return the user id (int)."""
    try:
        payload = jwt.decode(token, settings.api_jwt_secret, algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError as exc:  # covers expiry / bad signature / malformed
        raise HTTPException(status_code=401, detail="invalid token") from exc
    return int(payload["sub"])


def require_app_user(authorization: str = Header(...)) -> int:
    """App→API dependency: `Authorization: Bearer <app token>` → user id."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="invalid token")
    return verify_app_token(authorization[len("Bearer ") :])
