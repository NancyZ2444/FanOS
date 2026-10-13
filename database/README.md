# Database assets

- SQLAlchemy source of truth: `apps/api/app/models.py`
- Alembic migrations: `apps/api/migrations/versions/`
- Development seed: `apps/api/app/seed.py`
- Data dictionary: `database/docs/DATA_DICTIONARY.md`

Every schema change must update the ORM model, create an Alembic migration,
refresh OpenAPI when affected, and pass `alembic check`.
