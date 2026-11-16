"""add suggestion_log and demo flags

Revision ID: c81d4f7e2a05
Revises: 9f2aa888e3a3
Create Date: 2026-11-17 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c81d4f7e2a05'
down_revision: Union[str, Sequence[str], None] = '9f2aa888e3a3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'suggestion_log',
        sa.Column('id', sa.BigInteger(), nullable=False),
        sa.Column('user_id', sa.BigInteger(), nullable=False),
        sa.Column('slot_date', sa.Date(), nullable=False),
        sa.Column('weekday', sa.Integer(), nullable=False),
        sa.Column('start_min', sa.Integer(), nullable=False),
        sa.Column('sent_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'slot_date', 'start_min', name='uq_suggestion_once_per_slot'),
    )
    op.add_column(
        'hima_sessions',
        sa.Column('demo', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    )
    op.add_column(
        'regular_slots',
        sa.Column('demo', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('regular_slots', 'demo')
    op.drop_column('hima_sessions', 'demo')
    op.drop_table('suggestion_log')
