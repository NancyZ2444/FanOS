"""catalog localized names and optional album sides

Revision ID: 7c31e9a8d4b2
Revises: 2f07d5c4a921
Create Date: 2026-09-16 16:30:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "7c31e9a8d4b2"
down_revision: str | None = "2f07d5c4a921"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _localized_name_columns(table: str) -> None:
    op.add_column(
        table,
        sa.Column("name_en", sa.String(length=180), server_default="", nullable=False),
    )
    op.add_column(
        table,
        sa.Column("name_ko", sa.String(length=180), server_default="", nullable=False),
    )
    op.add_column(
        table,
        sa.Column("name_translated", sa.String(length=180), server_default="", nullable=False),
    )


def upgrade() -> None:
    for table in ("groups", "idols", "catalog_albums", "catalog_events", "catalog_merchandise"):
        _localized_name_columns(table)

    op.add_column(
        "cards",
        sa.Column("title_en", sa.String(length=220), server_default="", nullable=False),
    )
    op.add_column(
        "cards",
        sa.Column("title_ko", sa.String(length=220), server_default="", nullable=False),
    )
    op.add_column(
        "cards",
        sa.Column("title_translated", sa.String(length=220), server_default="", nullable=False),
    )
    op.add_column(
        "catalog_albums",
        sa.Column("front_image_url", sa.String(length=500), nullable=True),
    )
    op.add_column(
        "catalog_albums",
        sa.Column("back_image_url", sa.String(length=500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("catalog_albums", "back_image_url")
    op.drop_column("catalog_albums", "front_image_url")
    op.drop_column("cards", "title_translated")
    op.drop_column("cards", "title_ko")
    op.drop_column("cards", "title_en")
    for table in reversed(
        ("groups", "idols", "catalog_albums", "catalog_events", "catalog_merchandise")
    ):
        op.drop_column(table, "name_translated")
        op.drop_column(table, "name_ko")
        op.drop_column(table, "name_en")
