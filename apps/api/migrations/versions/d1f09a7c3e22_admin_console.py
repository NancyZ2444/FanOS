"""Admin catalog workflow, image provenance and import tasks.

Revision ID: d1f09a7c3e22
Revises: a8e42c19f5d0
"""

import sqlalchemy as sa
from alembic import op

revision = "d1f09a7c3e22"
down_revision = "a8e42c19f5d0"
branch_labels = None
depends_on = None


def timestamps():
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    ]


def upgrade():
    with op.batch_alter_table("cards") as batch:
        batch.alter_column("idol_id", existing_type=sa.String(64), nullable=True)
        batch.add_column(
            sa.Column("status", sa.String(30), nullable=False, server_default="PUBLISHED")
        )
        batch.add_column(sa.Column("admin_data", sa.JSON(), nullable=False, server_default="{}"))
        batch.create_index("ix_cards_status", ["status"])
    op.create_table(
        "admin_content_metadata",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("entity_type", sa.String(40), nullable=False),
        sa.Column("entity_id", sa.String(64), nullable=False),
        sa.Column("status", sa.String(30), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("operator_id", sa.String(64), nullable=False),
        *timestamps(),
        sa.UniqueConstraint("entity_type", "entity_id"),
        if_not_exists=True,
    )
    for col in ("entity_type", "entity_id", "status"):
        op.create_index(
            f"ix_admin_content_metadata_{col}", "admin_content_metadata", [col], if_not_exists=True
        )
    op.create_table(
        "catalog_collections",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(180), nullable=False),
        sa.Column("group_id", sa.String(64), sa.ForeignKey("groups.id"), nullable=False),
        sa.Column("entity_type", sa.String(30), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("release_date", sa.String(20), nullable=False),
        sa.Column("image_url", sa.String(500)),
        *timestamps(),
        if_not_exists=True,
    )
    op.create_index(
        "ix_catalog_collections_group_id", "catalog_collections", ["group_id"], if_not_exists=True
    )
    op.create_table(
        "card_image_versions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("card_id", sa.String(64), sa.ForeignKey("cards.id"), nullable=False),
        sa.Column("side", sa.String(10), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("operator_id", sa.String(64), nullable=False),
        *timestamps(),
        if_not_exists=True,
    )
    op.create_index(
        "ix_card_image_versions_card_id", "card_image_versions", ["card_id"], if_not_exists=True
    )
    op.create_table(
        "admin_import_tasks",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("filename", sa.String(240), nullable=False),
        sa.Column("status", sa.String(30), nullable=False),
        sa.Column("rows", sa.JSON(), nullable=False),
        sa.Column("errors", sa.JSON(), nullable=False),
        sa.Column("imported_count", sa.Integer(), nullable=False),
        sa.Column("operator_id", sa.String(64), nullable=False),
        *timestamps(),
        if_not_exists=True,
    )


def downgrade():
    # Group cards have no idol: refuse a lossy downgrade rather than delete data.
    if op.get_bind().execute(sa.text("SELECT count(*) FROM cards WHERE idol_id IS NULL")).scalar():
        raise RuntimeError("Cannot downgrade while group cards without an idol exist")

    for table in (
        "admin_import_tasks",
        "card_image_versions",
        "catalog_collections",
        "admin_content_metadata",
    ):
        op.drop_table(table)
    with op.batch_alter_table("cards") as batch:
        batch.drop_index("ix_cards_status")
        batch.drop_column("admin_data")
        batch.drop_column("status")
        batch.alter_column("idol_id", existing_type=sa.String(64), nullable=False)
