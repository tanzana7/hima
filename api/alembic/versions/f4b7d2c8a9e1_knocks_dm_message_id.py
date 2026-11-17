"""knocks: dm_message_id

Revision ID: f4b7d2c8a9e1
Revises: a7c3e9b1d4f2
Create Date: 2026-11-17 02:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f4b7d2c8a9e1'
down_revision: Union[str, Sequence[str], None] = 'a7c3e9b1d4f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('knocks', sa.Column('dm_message_id', sa.BigInteger(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('knocks', 'dm_message_id')
