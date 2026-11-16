"""guilds: base_topic and topic_counter

Revision ID: a7c3e9b1d4f2
Revises: c81d4f7e2a05
Create Date: 2026-11-17 01:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7c3e9b1d4f2'
down_revision: Union[str, Sequence[str], None] = 'c81d4f7e2a05'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('guilds', sa.Column('base_topic', sa.Text(), nullable=True))
    op.add_column('guilds', sa.Column('topic_counter', sa.Integer(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('guilds', 'topic_counter')
    op.drop_column('guilds', 'base_topic')
