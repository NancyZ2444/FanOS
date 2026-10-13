"""Store unsigned 32-bit ARGB colors without PostgreSQL integer overflow."""

from alembic import op
import sqlalchemy as sa

revision = "e612_color_bigint"
down_revision = "d611_catalog_taxonomy"
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    if connection.dialect.name != "postgresql":
        return
    inspector = sa.inspect(connection)
    for table in inspector.get_table_names():
        for column in inspector.get_columns(table):
            if column["name"] in {"color_start", "color_end"} and not isinstance(
                column["type"], sa.BigInteger
            ):
                op.alter_column(
                    table,
                    column["name"],
                    existing_type=column["type"],
                    type_=sa.BigInteger(),
                    existing_nullable=column["nullable"],
                )


def downgrade():
    raise RuntimeError("ARGB values may exceed INTEGER; restore a backup to downgrade.")
