"""Public attribution from adopted user submissions, never catalog operators.

This is a read projection over existing review/audit records. A backend-created
entity, an initialization revision, or an unadopted suggestion is not a user
contribution. No historical data is inferred or manufactured here.
"""

from sqlalchemy import select

from app.admin_models import CardImageVersion
from app.models import User
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.feedback.models import CardContribution, Feedback


def catalog_credits(db, kind, entity_id):
    adopted = db.scalars(
        select(Feedback)
        .where(
            Feedback.entity_type == kind,
            Feedback.entity_id == entity_id,
            Feedback.status == "PROCESSED",
            Feedback.result == "INCLUDED",
        )
        .order_by(Feedback.created_at, Feedback.id)
    ).all()
    entries = []
    if kind == "cards":
        images = db.scalars(
            select(CardContribution)
            .join(Feedback, Feedback.id == CardContribution.feedback_id)
            .where(
                CardContribution.card_id == entity_id,
                Feedback.user_id == CardContribution.user_id,
                Feedback.entity_type == "cards",
                Feedback.entity_id == entity_id,
                Feedback.status == "PROCESSED",
                Feedback.result == "INCLUDED",
            )
            .order_by(CardContribution.created_at, CardContribution.id)
        ).all()
        for row in images:
            version = db.get(CardImageVersion, row.image_version_id)
            entries.append(
                (
                    row.created_at,
                    row.user_id,
                    version.data.get("copyright_status", "UNKNOWN") if version else "UNKNOWN",
                )
            )
    for row in adopted:
        if row.kind == "CORRECTION" and any(
            decision.get("decision") in {"ACCEPT", "MODIFY"}
            for decision in row.review.get("decisions", [])
        ):
            entries.append((row.updated_at, row.user_id, "UNKNOWN"))
        elif row.kind == "MISSING_CATALOG" and row.review.get("adopted_fields"):
            # This workflow sets INCLUDED only after publishing the linked
            # formal object. Merely drafting or matching existing data does not.
            entries.append((row.updated_at, row.user_id, "UNKNOWN"))

    # The pre-unified user review workflow also has explicit adoption records.
    # Keep these genuine credits, but never inspect creator/operator metadata.
    legacy = db.scalars(
        select(CatalogRecord).where(
            CatalogRecord.kind == "reviews",
            CatalogRecord.entity_type == kind,
            CatalogRecord.entity_id == entity_id,
            CatalogRecord.status == "ACCEPTED",
        )
    ).all()
    for row in legacy:
        if row.data.get("contributor") and row.data.get("suggested"):
            entries.append((row.updated_at, row.data["contributor"], "UNKNOWN"))

    # A real profile change can affect a related group/idol as well (e.g. a
    # membership correction). Its immutable revision retains the same adopted
    # submission, so credit the affected profile without inventing another row.
    if kind in {"groups", "idols"}:
        versions = db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "profile_versions",
                CatalogRecord.entity_type == kind,
                CatalogRecord.entity_id == entity_id,
                CatalogRecord.status == "PUBLISHED",
            )
        ).all()
        for version in versions:
            data = version.data
            user_id = data.get("author", {}).get("id")
            if data.get("source") != "USER" or not user_id or not data.get("changes"):
                continue
            feedback = (
                db.get(Feedback, data.get("submission_id")) if data.get("submission_id") else None
            )
            if (
                feedback
                and feedback.user_id == user_id
                and feedback.status == "PROCESSED"
                and feedback.result == "INCLUDED"
            ):
                entries.append((version.created_at, user_id, "UNKNOWN"))

    users = {}
    for included_at, user_id, copyright_status in sorted(entries, key=lambda item: item[0]):
        if user_id in users:
            continue
        user = db.get(User, user_id)
        if user is None:
            continue
        # Missing/deactivated accounts are never linked to a live profile.
        users[user_id] = {
            "user_id": user_id if user and user.is_active else None,
            "name": user.display_name if user and user.is_active else "已注销用户",
            "profile_available": bool(user and user.is_active),
            "included_at": included_at.isoformat(),
            "source_type": "USER_SUBMITTED",
            # Preserve the existing API contract; this is no longer UI prose.
            "copyright_status": copyright_status,
        }
    return list(users.values())
