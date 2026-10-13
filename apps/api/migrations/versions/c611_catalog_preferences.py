"""Explicit favorite highlight, private display names, event platform and card serials."""

import json
from uuid import uuid4

import sqlalchemy as sa
from alembic import op

revision = "c611_catalog_preferences"
down_revision = "a611_digital_albums"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("primary_idol_id", sa.String(64), nullable=True))
    op.add_column(
        "users", sa.Column("name_preferences", sa.JSON(), nullable=False, server_default="{}")
    )
    op.add_column(
        "catalog_events", sa.Column("platform", sa.String(120), nullable=False, server_default="")
    )
    op.add_column("cards", sa.Column("card_number", sa.String(40), nullable=True))
    db = op.get_bind()
    # Preserve each existing user's highlight once. Future null values stay null.
    db.execute(
        sa.text("""
        UPDATE users SET primary_idol_id = (
            SELECT idol_id FROM user_idols WHERE user_id = users.id
            AND relation_type = 'favorite' ORDER BY priority, idol_id LIMIT 1
        )
    """)
    )
    for row in db.execute(sa.text("SELECT id, admin_data FROM cards")).mappings().all():
        data = row["admin_data"]
        data = json.loads(data) if isinstance(data, str) else (data or {})
        if data.get("card_number"):
            data["legacy_card_number"] = data.pop("card_number")
        db.execute(
            sa.text("UPDATE cards SET card_number=:number, admin_data=:data WHERE id=:id"),
            {
                "id": row["id"],
                "number": f"FOS-{uuid4().hex.upper()}",
                "data": json.dumps(data),
            },
        )
    with op.batch_alter_table("cards") as batch:
        batch.alter_column("card_number", existing_type=sa.String(40), nullable=False)
        batch.create_unique_constraint("uq_cards_card_number", ["card_number"])


def downgrade():
    with op.batch_alter_table("cards") as batch:
        batch.drop_constraint("uq_cards_card_number", type_="unique")
        batch.drop_column("card_number")
    op.drop_column("catalog_events", "platform")
    op.drop_column("users", "name_preferences")
    op.drop_column("users", "primary_idol_id")
