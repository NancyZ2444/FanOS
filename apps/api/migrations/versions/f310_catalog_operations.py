"""Enable solo ownership and additive operational records without changing IDs."""

import sqlalchemy as sa
from alembic import op

revision = "f310_catalog_operations"
down_revision = "e2a10b8f4c63"
branch_labels = None
depends_on = None


def upgrade():
    for table in (
        "cards",
        "catalog_albums",
        "catalog_events",
        "catalog_merchandise",
        "catalog_collections",
    ):
        with op.batch_alter_table(table) as batch:
            batch.alter_column("group_id", existing_type=sa.String(64), nullable=True)
    op.create_table(
        "catalog_operational_records",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("kind", sa.String(40), nullable=False),
        sa.Column("entity_type", sa.String(40), nullable=False),
        sa.Column("entity_id", sa.String(64), nullable=False),
        sa.Column("status", sa.String(30), nullable=False),
        sa.Column("data", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("kind", "id"),
    )
    for name in ("kind", "entity_type", "entity_id", "status"):
        op.create_index(
            f"ix_catalog_operational_records_{name}", "catalog_operational_records", [name]
        )


def downgrade():
    bind = op.get_bind()
    tables = (
        "cards",
        "catalog_albums",
        "catalog_events",
        "catalog_merchandise",
        "catalog_collections",
    )
    if bind.execute(sa.text("SELECT count(*) FROM catalog_operational_records")).scalar() or any(
        bind.execute(sa.text(f"SELECT count(*) FROM {t} WHERE group_id IS NULL")).scalar()
        for t in tables
    ):
        raise RuntimeError("Export new operational records and solo data before downgrade")
    op.drop_table("catalog_operational_records")
    for table in tables:
        with op.batch_alter_table(table) as batch:
            batch.alter_column("group_id", existing_type=sa.String(64), nullable=False)
