"""デモ用ダミー履歴の投入スクリプト（Phase C）。

過去4週間分の「終了済み」ヒマセッションを投入する。
- 実ユーザー2人（引数で受ける）＋ダミーユーザー3人
- 平日は 22時台に宣言が多い、週末は午後に出る、という曜日×時間の偏りを持たせる
- 実ユーザー2人には regular_slots（平日22:00〜23:59）も登録する
- --reset で投入した分だけを削除する（demo フラグで識別）

使い方:
    .venv/Scripts/python scripts/seed_demo_history.py <ユーザーのDiscord ID> <yoimaのDiscord ID>
    .venv/Scripts/python scripts/seed_demo_history.py --reset <id1> <id2>
"""
from __future__ import annotations

import argparse
import random
import sys
from datetime import datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import text  # noqa: E402

from api.db import SessionLocal  # noqa: E402
from api.models import HimaSession, Membership, RegularSlot, User  # noqa: E402
from api.vocab import ACTIVITIES  # noqa: E402

TZ = ZoneInfo("Asia/Tokyo")

# 実在しない大きな ID（デモユーザー）。display_name に「デモ・」を付ける。
DEMO_USER_IDS = [990000000000000001, 990000000000000002, 990000000000000003]
DEMO_NAMES = ["デモ・みか", "デモ・そら", "デモ・かい"]
DEFAULT_GUILD_ID = 1570807158818209872  # 開発ギルド（デモユーザーの所属先）
SEED_DAYS = 28  # 過去4週間（各曜日ちょうど4回）

# 平日: 22:00〜22:25 に開始、60〜90分 / 週末: 14:00〜16:00 に開始、90〜150分
WEEKDAY_START_OFFSET = 25  # 22:00 + 0..25 分
WEEKDAY_DURATIONS = [60, 75, 90]
WEEKEND_START_OFFSET = 120  # 14:00 + 0..120 分
WEEKEND_DURATIONS = [90, 120, 150]


def _pick(rng: random.Random, weights: list[float]) -> int:
    r = rng.random()
    acc = 0.0
    for i, w in enumerate(weights):
        acc += w
        if r < acc:
            return i
    return len(weights) - 1


def seed(real_ids: list[int], guild_id: int) -> None:
    rng = random.Random(20261116)  # 再現性のため固定シード
    now = datetime.now(TZ)
    with SessionLocal() as db:
        db.execute(text(
            "INSERT INTO guilds (id, name) VALUES (:g, :n) ON CONFLICT (id) DO NOTHING"
        ), {"g": guild_id, "n": "デモギルド"})
        all_ids = real_ids + DEMO_USER_IDS
        for i, uid in enumerate(all_ids):
            user = db.get(User, uid)
            if user is None:
                name = DEMO_NAMES[i - len(real_ids)] if uid in DEMO_USER_IDS else f"デモ参加者{uid % 10000:04d}"
                db.add(User(id=uid, display_name=name))
        db.flush()  # ユーザーを先に確定させる（FK 順序対策）
        for uid in DEMO_USER_IDS:
            m = db.get(Membership, (guild_id, uid))
            if m is None:
                db.add(Membership(guild_id=guild_id, user_id=uid, visible=True))

        for days_ago in range(SEED_DAYS, 0, -1):
            day = now.date() - timedelta(days=days_ago)
            is_weekend = day.weekday() >= 5
            for uid in all_ids:
                if is_weekend:
                    start_min = 14 * 60 + rng.randint(0, WEEKEND_START_OFFSET)
                    duration = rng.choice(WEEKEND_DURATIONS)
                else:
                    start_min = 22 * 60 + rng.randint(0, WEEKDAY_START_OFFSET)
                    duration = rng.choice(WEEKDAY_DURATIONS)
                started = datetime.combine(day, time.min, tzinfo=TZ) + timedelta(minutes=start_min)
                ended = started + timedelta(minutes=duration)
                if ended > now:
                    ended = now
                if ended <= started:
                    continue
                mood = ["ok", "moon"][_pick(rng, [0.7, 0.3])]  # fire 廃止により 2 値
                source = ["manual", "suggested", "auto"][_pick(rng, [0.7, 0.2, 0.1])]
                db.add(
                    HimaSession(
                        user_id=uid,
                        mood=mood,
                        activity=rng.choice(list(ACTIVITIES)),
                        note=None,
                        source=source,
                        started_at=started,
                        expires_at=ended,
                        ended_at=ended,
                        demo=True,
                    )
                )

        for uid in real_ids:  # 平日22:00〜23:59
            for wd in range(5):
                db.add(RegularSlot(user_id=uid, weekday=wd, start_min=22 * 60, end_min=23 * 60 + 59, demo=True))
        db.commit()

        sessions = db.query(HimaSession).filter(HimaSession.demo == True).count()  # noqa: E712
        slots = db.query(RegularSlot).filter(RegularSlot.demo == True).count()  # noqa: E712
        print(f"seeded: {sessions} demo sessions, {slots} demo regular_slots")


def reset(guild_id: int) -> None:
    with SessionLocal() as db:
        db.execute(text(
            "DELETE FROM watch_queue WHERE session_id IN (SELECT id FROM hima_sessions WHERE demo)"
        ))
        db.execute(text(
            "DELETE FROM matches WHERE session_a_id IN (SELECT id FROM hima_sessions WHERE demo) "
            "OR session_b_id IN (SELECT id FROM hima_sessions WHERE demo)"
        ))
        db.query(HimaSession).filter(HimaSession.demo == True).delete(synchronize_session=False)  # noqa: E712
        db.query(RegularSlot).filter(RegularSlot.demo == True).delete(synchronize_session=False)  # noqa: E712
        for uid in DEMO_USER_IDS:
            db.query(Membership).filter(Membership.user_id == uid).delete(synchronize_session=False)
            if db.get(User, uid) is not None:
                db.delete(db.get(User, uid))
        db.commit()
        sessions = db.query(HimaSession).filter(HimaSession.demo == True).count()  # noqa: E712
        print(f"reset done: {sessions} demo sessions remain")


def main() -> None:
    parser = argparse.ArgumentParser(description="seed demo hima history (4 weeks)")
    parser.add_argument("user_id", nargs=2, help="実ユーザー2人の Discord ID（あなたと yoima）")
    parser.add_argument("--reset", action="store_true", help="投入したデモデータを削除する")
    parser.add_argument("--guild-id", type=int, default=DEFAULT_GUILD_ID)
    args = parser.parse_args()
    real_ids = [int(x) for x in args.user_id]
    if args.reset:
        reset(args.guild_id)
    else:
        seed(real_ids, args.guild_id)


if __name__ == "__main__":
    main()
