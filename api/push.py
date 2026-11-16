"""FCM push notifications. Dry-run by default (FCM_SERVICE_ACCOUNT_JSON unset).

Failures are logged and never break the request that triggered them.
"""
from __future__ import annotations

import json
import logging
import os
import time

import httpx
import jwt

from .models import Device

log = logging.getLogger("atsumaro.push")

FCM_SCOPES = "https://www.googleapis.com/auth/firebase.messaging"


def _service_account_path() -> str | None:
    return os.getenv("FCM_SERVICE_ACCOUNT_JSON") or None


def _access_token(service_account: dict) -> str:
    now = int(time.time())
    assertion = jwt.encode(
        {
            "iss": service_account["client_email"],
            "scope": FCM_SCOPES,
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
        },
        service_account["private_key"],
        algorithm="RS256",
    )
    resp = httpx.post(
        "https://oauth2.googleapis.com/token",
        data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        timeout=10.0,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def send_push(db, user_id: int, title: str, body: str) -> None:
    """Send a push to all registered devices of the user (no-op without devices).

    FCM_SERVICE_ACCOUNT_JSON unset → dry-run: log only (hackathon default).
    """
    try:
        tokens = [row[0] for row in db.query(Device.fcm_token).filter(Device.user_id == user_id).all()]
        if not tokens:
            return
        path = _service_account_path()
        if path is None:
            log.info(
                "[push dry-run] user=%s devices=%d title=%r body=%r", user_id, len(tokens), title, body
            )
            return
        with open(path, encoding="utf-8") as fh:
            service_account = json.load(fh)
        access = _access_token(service_account)
        project = service_account["project_id"]
        with httpx.Client(timeout=10.0) as client:
            for token in tokens:
                resp = client.post(
                    f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
                    json={"message": {"token": token, "notification": {"title": title, "body": body}}},
                    headers={"Authorization": f"Bearer {access}"},
                )
                if resp.status_code >= 400:
                    log.warning(
                        "fcm send failed user=%s token=%s…: HTTP %s %s",
                        user_id, token[:8], resp.status_code, resp.text[:200],
                    )
        log.info("push sent user=%s devices=%d", user_id, len(tokens))
    except Exception:  # noqa: BLE001 - push failures never break requests
        log.exception("push failed (ignored) user=%s", user_id)
