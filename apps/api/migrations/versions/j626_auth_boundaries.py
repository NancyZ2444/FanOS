"""V1.5 isolated principals, sessions and one-time verification challenges.

Additive migration only. Existing App user IDs, roles, assets and legacy social
rows are retained. Legacy roles and unverified social rows convey no auth rights.
Administrator credentials must be explicitly provisioned via bootstrap_admin.py.
"""

from alembic import op

from app.auth_models import (
    AdminPrincipal,
    AuthAudit,
    AuthSession,
    AuthState,
    LoginWhitelist,
    TrustedIdentity,
    VerificationChallenge,
)

revision = "j626_auth_boundaries"
down_revision = "i622_album_work_types"
branch_labels = None
depends_on = None
MODELS = (
    AdminPrincipal,
    AuthSession,
    AuthState,
    VerificationChallenge,
    LoginWhitelist,
    TrustedIdentity,
    AuthAudit,
)


def upgrade():
    bind = op.get_bind()
    for model in MODELS:
        model.__table__.create(bind, checkfirst=True)
    if not bind.execute(AuthState.__table__.select().where(AuthState.id == "auth-lock")).first():
        bind.execute(
            AuthState.__table__.insert().values(id="auth-lock", kind="lock", data={}, version=1)
        )


def downgrade():
    raise RuntimeError(
        "Authentication audit/session tables must not be dropped automatically; "
        "restore an approved backup instead."
    )
