"""catalog discovery entities

Revision ID: 2f07d5c4a921
Revises: 105bc28ba410
Create Date: 2026-09-16 12:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "2f07d5c4a921"
down_revision: str | None = "105bc28ba410"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "groups", sa.Column("debut_date", sa.String(length=20), server_default="", nullable=False)
    )
    op.add_column(
        "groups", sa.Column("region", sa.String(length=80), server_default="", nullable=False)
    )
    op.add_column(
        "idols", sa.Column("company", sa.String(length=120), server_default="", nullable=False)
    )
    op.add_column(
        "idols", sa.Column("birth_date", sa.String(length=20), server_default="", nullable=False)
    )
    op.add_column(
        "idols", sa.Column("region", sa.String(length=80), server_default="", nullable=False)
    )
    op.add_column(
        "idols", sa.Column("role", sa.String(length=100), server_default="", nullable=False)
    )
    op.add_column(
        "idols", sa.Column("careers", sa.JSON(), server_default=sa.text("'[]'"), nullable=False)
    )

    timestamp_columns = (
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_table(
        "catalog_albums",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=180), nullable=False),
        sa.Column("artist_name", sa.String(length=180), nullable=False),
        sa.Column("group_id", sa.String(length=64), nullable=False),
        sa.Column("release_date", sa.String(length=20), nullable=False),
        sa.Column("album_type", sa.String(length=80), nullable=False),
        sa.Column("versions", sa.JSON(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("color_start", sa.Integer(), nullable=False),
        sa.Column("color_end", sa.Integer(), nullable=False),
        sa.Column("image_url", sa.String(length=500), nullable=True),
        sa.Column("is_published", sa.Boolean(), nullable=False),
        *timestamp_columns,
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_catalog_albums_name", "catalog_albums", ["name"])
    op.create_index("ix_catalog_albums_group_id", "catalog_albums", ["group_id"])
    op.create_index("ix_catalog_albums_release_date", "catalog_albums", ["release_date"])
    op.create_index("ix_catalog_albums_album_type", "catalog_albums", ["album_type"])
    op.create_index("ix_catalog_albums_is_published", "catalog_albums", ["is_published"])

    op.create_table(
        "catalog_events",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=180), nullable=False),
        sa.Column("artist_name", sa.String(length=180), nullable=False),
        sa.Column("group_id", sa.String(length=64), nullable=False),
        sa.Column("event_type", sa.String(length=80), nullable=False),
        sa.Column("start_date", sa.String(length=20), nullable=False),
        sa.Column("region", sa.String(length=80), nullable=False),
        sa.Column("city", sa.String(length=100), nullable=False),
        sa.Column("venue", sa.String(length=180), nullable=False),
        sa.Column("parent_event_id", sa.String(length=64), nullable=True),
        sa.Column("is_online", sa.Boolean(), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("color_start", sa.Integer(), nullable=False),
        sa.Column("color_end", sa.Integer(), nullable=False),
        sa.Column("image_url", sa.String(length=500), nullable=True),
        sa.Column("is_published", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
        sa.ForeignKeyConstraint(["parent_event_id"], ["catalog_events.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_catalog_events_name", "catalog_events", ["name"])
    op.create_index("ix_catalog_events_group_id", "catalog_events", ["group_id"])
    op.create_index("ix_catalog_events_event_type", "catalog_events", ["event_type"])
    op.create_index("ix_catalog_events_start_date", "catalog_events", ["start_date"])
    op.create_index("ix_catalog_events_region", "catalog_events", ["region"])
    op.create_index("ix_catalog_events_parent_event_id", "catalog_events", ["parent_event_id"])
    op.create_index("ix_catalog_events_is_published", "catalog_events", ["is_published"])

    op.create_table(
        "catalog_merchandise",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("name", sa.String(length=180), nullable=False),
        sa.Column("artist_name", sa.String(length=180), nullable=False),
        sa.Column("group_id", sa.String(length=64), nullable=False),
        sa.Column("type", sa.String(length=80), nullable=False),
        sa.Column("source", sa.String(length=180), nullable=False),
        sa.Column("release_date", sa.String(length=20), nullable=False),
        sa.Column("region", sa.String(length=80), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("color_start", sa.Integer(), nullable=False),
        sa.Column("color_end", sa.Integer(), nullable=False),
        sa.Column("image_url", sa.String(length=500), nullable=True),
        sa.Column("is_published", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_catalog_merchandise_name", "catalog_merchandise", ["name"])
    op.create_index("ix_catalog_merchandise_group_id", "catalog_merchandise", ["group_id"])
    op.create_index("ix_catalog_merchandise_type", "catalog_merchandise", ["type"])
    op.create_index("ix_catalog_merchandise_release_date", "catalog_merchandise", ["release_date"])
    op.create_index("ix_catalog_merchandise_region", "catalog_merchandise", ["region"])
    op.create_index("ix_catalog_merchandise_is_published", "catalog_merchandise", ["is_published"])


def downgrade() -> None:
    op.drop_table("catalog_merchandise")
    op.drop_table("catalog_events")
    op.drop_table("catalog_albums")
    op.drop_column("idols", "careers")
    op.drop_column("idols", "role")
    op.drop_column("idols", "region")
    op.drop_column("idols", "birth_date")
    op.drop_column("idols", "company")
    op.drop_column("groups", "region")
    op.drop_column("groups", "debut_date")
