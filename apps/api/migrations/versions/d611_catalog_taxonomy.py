"""Other sources and entity-scoped tags; retain legacy source rows as archives."""

from alembic import op
from sqlalchemy.orm import Session

revision = "d611_catalog_taxonomy"
down_revision = "c611_catalog_preferences"
branch_labels = None
depends_on = None


def upgrade():
    from app.modules.catalog.taxonomy_models import CatalogOther, CatalogTag, CatalogTagBinding
    from app.modules.catalog.taxonomy_upgrade import migrate_taxonomy

    connection = op.get_bind()
    for model in (CatalogOther, CatalogTag, CatalogTagBinding):
        model.__table__.create(connection, checkfirst=True)
    with Session(bind=connection) as db:
        migrate_taxonomy(db)
        db.flush()
        # The Alembic connection owns the commit; don't commit outside it.


def downgrade():
    raise RuntimeError(
        "Taxonomy backfill preserves IDs but changes relationships. Restore the verified pre-upgrade backup instead of dropping live Other/tag records."
    )
