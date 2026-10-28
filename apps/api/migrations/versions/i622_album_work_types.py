"""V1.1 immutable work types and isolated card instances."""

import sqlalchemy as sa
from alembic import op

revision = "i622_album_work_types"
down_revision = "h620_album_operations"
branch_labels = None
depends_on = None


def upgrade():
    # Rendering migration must not reorder shelves or moderation queues.
    bind = op.get_bind()
    timestamps = {}
    for name in (
        "card_albums",
        "digital_album_pages",
        "digital_album_review_requests",
        "digital_album_resources",
    ):
        table = sa.Table(name, sa.MetaData(), autoload_with=bind)
        timestamps[name] = (table, list(bind.execute(sa.select(table.c.id, table.c.updated_at))))
    op.create_table(
        "digital_album_works",
        sa.Column("album_id", sa.String(64), sa.ForeignKey("card_albums.id"), primary_key=True),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("mode", sa.String(10), nullable=False),
        sa.Column("instances", sa.JSON(), nullable=False),
        sa.Column("request_id", sa.String(100)),
        sa.Column("request_fingerprint", sa.String(64)),
        sa.Column("migration_archive", sa.JSON()),
        sa.UniqueConstraint("user_id", "request_id"),
    )
    op.create_index("ix_digital_album_works_user_id", "digital_album_works", ["user_id"])
    with op.batch_alter_table("digital_album_resources") as batch:
        batch.alter_column("scene", existing_type=sa.String(10), type_=sa.String(24))
    from sqlalchemy.orm import Session

    from app.modules.albums.migration_v11 import migrate_materials, migrate_works

    with Session(bind=op.get_bind()) as db:
        from app.modules.albums.materials import backfill_snapshots

        backfill_snapshots(db)
        report = migrate_works(db)
        migrate_materials(db)
        db.flush()
        print("Album V1.1 migration:", report)
    for table, rows in timestamps.values():
        for row in rows:
            bind.execute(
                table.update().where(table.c.id == row.id).values(updated_at=row.updated_at)
            )


def downgrade():
    raise RuntimeError(
        "V1.1 stores independent instances; restore the verified pre-migration backup "
        "instead of dropping data"
    )
