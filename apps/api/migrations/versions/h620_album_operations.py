"""Digital album P0 moderation, material history and successful color usage."""

import sqlalchemy as sa
from alembic import op

revision = "h620_album_operations"
down_revision = "g614_feedback_workflow"
branch_labels = None
depends_on = None


def upgrade():
    for column in [
        sa.Column("publication_blocked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("moderation_status", sa.String(16), nullable=False, server_default="NORMAL"),
        sa.Column("moderation_reason", sa.String(200), nullable=False, server_default=""),
        sa.Column("moderation_note", sa.String(1000), nullable=False, server_default=""),
    ]:
        op.add_column("card_albums", column)
    op.execute("UPDATE card_albums SET moderation_status = 'RESTRICTED' WHERE is_moderated = true")
    op.add_column("digital_album_preferences", sa.Column("shelf_snapshot", sa.JSON()))
    for column in [
        sa.Column("scene", sa.String(10), nullable=False, server_default="BOTH"),
        sa.Column("membership", sa.String(10), nullable=False, server_default="ALL"),
        sa.Column("locked_preview", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("published_once", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("used_once", sa.Boolean(), nullable=False, server_default=sa.false()),
    ]:
        op.add_column("digital_album_resources", column)
    # Existing offline resources may previously have been published; preserve conservatively.
    op.execute("UPDATE digital_album_resources SET published_once = true")
    op.create_table(
        "digital_album_review_requests",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("album_id", sa.String(64), sa.ForeignKey("card_albums.id"), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("snapshot", sa.JSON(), nullable=False),
        sa.Column("reason", sa.String(500), nullable=False, server_default=""),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index(
        "ix_digital_album_review_requests_album_id", "digital_album_review_requests", ["album_id"]
    )
    op.create_table(
        "digital_album_color_extractions",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("request_id", sa.String(100), nullable=False),
        sa.Column("colors", sa.JSON(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.UniqueConstraint("user_id", "request_id"),
    )
    op.create_index(
        "ix_digital_album_color_extractions_user_id", "digital_album_color_extractions", ["user_id"]
    )
    # Backfill only missing render snapshots. Keep names, revisions, IDs and quotas intact.
    from sqlalchemy.orm import Session

    from app.modules.albums.materials import backfill_snapshots

    db = Session(bind=op.get_bind())
    try:
        # Current ORM also knows V1.1 works; fresh upgrade chains backfill in i622
        # after its table exists. Databases already at h620 are backed up by i622.
        result = (
            backfill_snapshots(db)
            if sa.inspect(op.get_bind()).has_table("digital_album_works")
            else {"missing_resources": []}
        )
        db.flush()
        if result["missing_resources"]:
            print(
                "Album materials requiring manual recovery:", ", ".join(result["missing_resources"])
            )
    finally:
        db.close()


def downgrade():
    op.drop_table("digital_album_color_extractions")
    op.drop_table("digital_album_review_requests")
    for name in ("used_once", "published_once", "locked_preview", "membership", "scene"):
        op.drop_column("digital_album_resources", name)
    op.drop_column("digital_album_preferences", "shelf_snapshot")
    for name in (
        "moderation_note",
        "moderation_reason",
        "moderation_status",
        "publication_blocked",
    ):
        op.drop_column("card_albums", name)
