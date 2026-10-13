"""Persist the catalog type of import tasks; legacy tasks are card imports."""

import sqlalchemy as sa
from alembic import op

revision = "e2a10b8f4c63"
down_revision = "e22a811c4b03"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "admin_import_tasks",
        sa.Column("kind", sa.String(30), nullable=False, server_default="cards"),
    )


def downgrade():
    # Non-card tasks cannot safely become card tasks after a downgrade.
    count = (
        op.get_bind()
        .execute(sa.text("SELECT count(*) FROM admin_import_tasks WHERE kind != 'cards'"))
        .scalar()
    )
    if count:
        raise RuntimeError("Cannot downgrade while non-card import tasks exist")
    with op.batch_alter_table("admin_import_tasks") as batch:
        batch.drop_column("kind")
