"""Extend existing card books without deleting legacy placements or user assets."""

import sqlalchemy as sa
from alembic import op

revision = "a611_digital_albums"
down_revision = "b610_profile_background"
branch_labels = None
depends_on = None


def timestamps():
    return [
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.current_timestamp(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.current_timestamp(),
        ),
    ]


def upgrade():
    for column in [
        sa.Column("description", sa.String(200), nullable=False, server_default=""),
        sa.Column("display_type", sa.String(10), nullable=False, server_default="SINGLE"),
        sa.Column("visual_style", sa.String(12), nullable=False, server_default="REALISTIC"),
        sa.Column("status", sa.String(12), nullable=False, server_default="PUBLISHED"),
        sa.Column("revision", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("cover_config", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("card_view_config", sa.JSON(), nullable=False, server_default="{}"),
        sa.Column("published_snapshot", sa.JSON(), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_moderated", sa.Boolean(), nullable=False, server_default=sa.false()),
    ]:
        op.add_column("card_albums", column)
    op.create_index("ix_card_albums_status", "card_albums", ["status"])
    op.create_table(
        "digital_album_pages",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "album_id",
            sa.String(64),
            sa.ForeignKey("card_albums.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("page_order", sa.Integer(), nullable=False),
        sa.Column("grid_count", sa.Integer(), nullable=False),
        sa.Column("page_config", sa.JSON(), nullable=False),
        *timestamps(),
    )
    op.create_index("ix_digital_album_pages_album_id", "digital_album_pages", ["album_id"])
    op.create_table(
        "digital_album_slots",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "page_id",
            sa.String(64),
            sa.ForeignKey("digital_album_pages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("slot_order", sa.Integer(), nullable=False),
        sa.Column("card_id", sa.String(64), sa.ForeignKey("cards.id")),
        *timestamps(),
    )
    op.create_index("ix_digital_album_slots_page_id", "digital_album_slots", ["page_id"])
    op.create_index("ix_digital_album_slots_card_id", "digital_album_slots", ["card_id"])
    op.create_table(
        "digital_album_reactions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id", sa.String(64), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("album_id", sa.String(64), sa.ForeignKey("card_albums.id"), nullable=False),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.UniqueConstraint("user_id", "album_id", "kind"),
        *timestamps(),
    )
    op.create_index("ix_digital_album_reactions_user_id", "digital_album_reactions", ["user_id"])
    op.create_index("ix_digital_album_reactions_album_id", "digital_album_reactions", ["album_id"])
    op.create_table(
        "digital_album_preferences",
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("shelf_theme", sa.String(40), nullable=False),
        sa.Column("view_mode", sa.String(10), nullable=False),
        *timestamps(),
    )
    op.create_table(
        "digital_album_entitlements",
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("plan", sa.String(10), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True)),
        *timestamps(),
    )
    op.create_table(
        "digital_album_settings",
        sa.Column("id", sa.String(40), primary_key=True),
        sa.Column("config", sa.JSON(), nullable=False),
        *timestamps(),
    )
    op.create_table(
        "digital_album_resources",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("status", sa.String(12), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("config", sa.JSON(), nullable=False),
        *timestamps(),
    )


def downgrade():
    for table in [
        "digital_album_resources",
        "digital_album_settings",
        "digital_album_entitlements",
        "digital_album_preferences",
        "digital_album_reactions",
        "digital_album_slots",
        "digital_album_pages",
    ]:
        op.drop_table(table)
    op.drop_index("ix_card_albums_status", table_name="card_albums")
    with op.batch_alter_table("card_albums") as batch:
        for name in [
            "is_moderated",
            "published_at",
            "published_snapshot",
            "card_view_config",
            "cover_config",
            "sort_order",
            "revision",
            "status",
            "visual_style",
            "display_type",
            "description",
        ]:
            batch.drop_column(name)
