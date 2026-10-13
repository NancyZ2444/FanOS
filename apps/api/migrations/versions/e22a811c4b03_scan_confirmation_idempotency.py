"""Track each detected physical card's collection write exactly once."""

import sqlalchemy as sa
from alembic import op

revision = "e22a811c4b03"
down_revision = "d1f09a7c3e22"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("detected_cards", sa.Column("owned_added_at", sa.DateTime(timezone=True)))
    # Older clients only submitted confirmed cards when adding to Owned.
    op.execute(
        "UPDATE detected_cards SET owned_added_at = updated_at "
        "WHERE user_confirmed_card_id IS NOT NULL"
    )


def downgrade():
    op.drop_column("detected_cards", "owned_added_at")
