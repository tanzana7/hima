"""add users.suggest_dm (opt-out for suggestion notifications)

Revision ID: e8a9c1d2b3f4
Revises: d6e0b2c4f8a1
Create Date: 2026-11-19 09:10:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e8a9c1d2b3f4'
down_revision: Union[str, Sequence[str], None] = 'd6e0b2c4f8a1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'users',
        sa.Column('suggest_dm', sa.Boolean(), nullable=False, server_default=sa.text('true')),
    )
    # 既存ユーザーは全員 true（オプトイン）に揃える
    op.execute("UPDATE users SET suggest_dm = true")


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('users', 'suggest_dm')
