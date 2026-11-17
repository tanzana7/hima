"""knocks template nullable

Revision ID: d6e0b2c4f8a1
Revises: c2a9d4e7f8b0
Create Date: 2026-11-17 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'd6e0b2c4f8a1'
down_revision: Union[str, Sequence[str], None] = 'c2a9d4e7f8b0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("ALTER TABLE knocks ALTER COLUMN template DROP NOT NULL")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("UPDATE knocks SET template = '' WHERE template IS NULL")
    op.execute("ALTER TABLE knocks ALTER COLUMN template SET NOT NULL")
