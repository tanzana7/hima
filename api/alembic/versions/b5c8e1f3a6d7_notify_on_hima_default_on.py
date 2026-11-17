"""notify_on_hima default on

Revision ID: b5c8e1f3a6d7
Revises: f4b7d2c8a9e1
Create Date: 2026-11-17 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b5c8e1f3a6d7'
down_revision: Union[str, Sequence[str], None] = 'f4b7d2c8a9e1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column(
        'users', 'notify_on_hima',
        existing_type=sa.Boolean(),
        server_default=sa.text('true'),
    )
    # 公開前の開発データのみのため、既存行も ON に揃える
    op.execute("UPDATE users SET notify_on_hima = true")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("UPDATE users SET notify_on_hima = false")
    op.alter_column(
        'users', 'notify_on_hima',
        existing_type=sa.Boolean(),
        server_default=sa.text('false'),
    )
