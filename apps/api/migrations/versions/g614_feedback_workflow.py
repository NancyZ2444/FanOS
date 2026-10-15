"""Add feedback workflow, uploaded image identity, attribution and reliable notices."""

import sqlalchemy as sa
from alembic import op

revision = "g614_feedback_workflow"
down_revision = "f614_album_favorite_groups"
branch_labels = None
depends_on = None


def timestamps():
    return [
        sa.Column(key, sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now())
        for key in ("created_at", "updated_at")
    ]


def upgrade():
    op.create_table(
        "catalog_user_feedback",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("request_key", sa.String(100), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("entity_type", sa.String(30), nullable=False),
        sa.Column("entity_id", sa.String(64), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("result", sa.String(20), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("public_note", sa.Text(), nullable=False),
        sa.Column("internal_note", sa.Text(), nullable=False),
        sa.Column("handler_id", sa.String(64)),
        *[
            sa.Column(key, sa.JSON(), nullable=False)
            for key in ("data", "review", "history", "action_keys")
        ],
        *timestamps(),
        sa.UniqueConstraint("user_id", "request_key"),
    )
    op.create_table(
        "catalog_feedback_images",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("image_url", sa.String(500), nullable=False),
        *timestamps(),
    )
    op.create_table(
        "catalog_card_contributions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("card_id", sa.String(64), sa.ForeignKey("cards.id"), nullable=False),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column(
            "feedback_id", sa.String(64), sa.ForeignKey("catalog_user_feedback.id"), nullable=False
        ),
        sa.Column(
            "image_version_id",
            sa.String(64),
            sa.ForeignKey("card_image_versions.id"),
            nullable=False,
        ),
        *timestamps(),
        sa.UniqueConstraint("feedback_id", "image_version_id"),
    )
    op.create_table(
        "catalog_feedback_notices",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("delivered", sa.Boolean(), nullable=False),
        sa.Column("error", sa.Text(), nullable=False),
        *timestamps(),
    )
    for table, keys in {
        "catalog_user_feedback": ["user_id", "kind", "entity_id", "status", "result", "handler_id"],
        "catalog_feedback_images": ["user_id"],
        "catalog_card_contributions": ["card_id", "user_id", "feedback_id"],
        "catalog_feedback_notices": ["user_id", "delivered"],
    }.items():
        for key in keys:
            op.create_index(f"ix_{table}_{key}", table, [key])


def downgrade():
    for table in (
        "catalog_feedback_notices",
        "catalog_card_contributions",
        "catalog_feedback_images",
        "catalog_user_feedback",
    ):
        op.drop_table(table)
