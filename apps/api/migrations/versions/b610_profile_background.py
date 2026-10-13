"""Persist the user-selected profile cover; existing profiles stay unchanged."""

import sqlalchemy as sa
from alembic import op

revision = "b610_profile_background"
down_revision = "f310_catalog_operations"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("background_url", sa.String(500), nullable=True))


def downgrade():
    with op.batch_alter_table("users") as batch:
        batch.drop_column("background_url")
