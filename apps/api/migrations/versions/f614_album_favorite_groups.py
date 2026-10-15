"""Private-by-default album favorite folders; existing favorites stay ungrouped."""

import sqlalchemy as sa
from alembic import op

revision = "f614_album_favorite_groups"
down_revision = "e612_color_bigint"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "digital_album_favorite_groups",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column(
            "user_id", sa.String(64), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("name", sa.String(40), nullable=False),
        sa.Column("is_public", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint("user_id", "name"),
    )
    op.create_index(
        "ix_digital_album_favorite_groups_user_id", "digital_album_favorite_groups", ["user_id"]
    )
    op.create_table(
        "digital_album_favorite_placements",
        sa.Column(
            "reaction_id",
            sa.String(64),
            sa.ForeignKey("digital_album_reactions.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "group_id",
            sa.String(64),
            sa.ForeignKey("digital_album_favorite_groups.id", ondelete="CASCADE"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_digital_album_favorite_placements_group_id",
        "digital_album_favorite_placements",
        ["group_id"],
    )


def downgrade():
    op.drop_table("digital_album_favorite_placements")
    op.drop_table("digital_album_favorite_groups")
