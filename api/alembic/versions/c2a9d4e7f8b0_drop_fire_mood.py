"""drop fire mood

Revision ID: c2a9d4e7f8b0
Revises: b5c8e1f3a6d7
Create Date: 2026-11-17 17:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'c2a9d4e7f8b0'
down_revision: Union[str, Sequence[str], None] = 'b5c8e1f3a6d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # users.auto_mood が fire の行は ok に寄せる
    op.execute("UPDATE users SET auto_mood = 'ok' WHERE auto_mood = 'fire'")
    # 有効セッションに fire が残っていても ok として扱われる（マッチング側で正規化）ため移行しない
    # matches の過去行（fire_fire / fire_ok）はそのまま残す


def downgrade() -> None:
    """Downgrade schema."""
    pass  # ok に寄せた auto_mood を fire に戻す情報は保持しない
