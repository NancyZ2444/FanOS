"""Distinguish a recorded membership from a verified historical start date."""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import GroupMembership, OperationLog


def create_undated_membership(db: Session, group_id: str, idol_id: str) -> GroupMembership:
    """Selecting a group proves the relationship, but supplies no joining date.

    Keep the legacy non-null database date for compatibility and explicitly mark
    it as a recording date, rather than inventing a historical joining date.
    """
    from .catalog_extensions import CatalogRecord

    membership = GroupMembership(group_id=group_id, idol_id=idol_id)
    db.add(membership)
    db.flush()
    db.add(
        CatalogRecord(
            kind="memberships",
            entity_type="idols",
            entity_id=idol_id,
            data={
                "membership_id": membership.id,
                "group_id": group_id,
                "status": membership.status,
                "start_date": "",
                "end_date": "",
                "date_unknown": True,
                "recorded_start_date": membership.start_date.isoformat(),
                "origin": "AUTO_GROUP_SELECTION",
            },
        )
    )
    return membership


def membership_start_is_unknown(
    db: Session, membership: GroupMembership, *, records=None, audits=None
) -> bool:
    """Only relax a start date when its automatic origin is evidenced.

    A matching calendar date alone is not evidence. Explicit member-history
    records always take precedence; legacy inference additionally requires an
    unchanged relation and the audit of the automatic creation path.
    """
    from .catalog_extensions import CatalogRecord

    extensions = [
        row
        for row in (
            records
            if records is not None
            else db.scalars(
                select(CatalogRecord).where(
                    CatalogRecord.kind == "memberships",
                    CatalogRecord.entity_id == membership.idol_id,
                )
            )
        )
        if row.data.get("membership_id") == membership.id
    ]
    if extensions:
        # Any explicitly maintained period takes precedence over an old marker.
        if any(row.data.get("start_date") for row in extensions):
            return False
        return any(
            row.data.get("date_unknown") is True
            and row.data.get("origin") == "AUTO_GROUP_SELECTION"
            and row.data.get("recorded_start_date") == membership.start_date.isoformat()
            for row in extensions
        )

    if not membership.created_at or not membership.updated_at:
        return False
    created_at = membership.created_at.replace(tzinfo=None)
    updated_at = membership.updated_at.replace(tzinfo=None)
    if membership.start_date != created_at.date() or abs(updated_at - created_at) > timedelta(
        seconds=1
    ):
        return False

    logs = (
        audits
        if audits is not None
        else db.scalars(
            select(OperationLog).where(
                OperationLog.action.in_(["catalog.entity.save", "catalog.membership.import"]),
                OperationLog.target_id.in_([membership.idol_id, membership.id]),
                OperationLog.created_at >= created_at,
                OperationLog.created_at <= created_at + timedelta(minutes=1),
            )
        )
    )
    for log in logs:
        after = log.after or {}
        if (
            not created_at
            <= log.created_at.replace(tzinfo=None)
            <= created_at + timedelta(minutes=1)
        ):
            continue
        if log.before or after.get("group_id") != membership.group_id:
            continue
        if log.action == "catalog.entity.save" and log.target_type == "idols":
            # save_entity creates the relation only for a new idol whose form
            # chooses a group. That form does not collect a membership date.
            if (
                log.target_id == membership.idol_id
                and after.get("id") == membership.idol_id
                and not after.get("start_date")
                and not after.get("membership_start_date")
            ):
                return True
        if log.action == "catalog.membership.import" and log.target_type == "memberships":
            # The combined importer also creates undated links for existing idols.
            if (
                log.target_id == membership.id
                and after.get("id") == membership.id
                and after.get("idol_id") == membership.idol_id
                and after.get("start_date") == membership.start_date.isoformat()
            ):
                return True
    return False


def membership_date_info(db: Session, memberships) -> dict[str, dict]:
    """Read date display metadata with two batched queries, not per-member queries."""
    from .catalog_extensions import CatalogRecord

    memberships = list(memberships)
    if not memberships:
        return {}
    idol_ids = {m.idol_id for m in memberships}
    member_ids = {m.id for m in memberships}
    records = list(
        db.scalars(
            select(CatalogRecord).where(
                CatalogRecord.kind == "memberships", CatalogRecord.entity_id.in_(idol_ids)
            )
        )
    )
    audits = list(
        db.scalars(
            select(OperationLog).where(
                OperationLog.action.in_(["catalog.entity.save", "catalog.membership.import"]),
                OperationLog.target_id.in_(idol_ids | member_ids),
            )
        )
    )
    result = {}
    for m in memberships:
        unknown = membership_start_is_unknown(db, m, records=records, audits=audits)
        result[m.id] = {
            "start_date": "" if unknown else m.start_date.isoformat(),
            "date_unknown": unknown,
        }
    return result


def membership_covers_release(db: Session, membership: GroupMembership, released: date) -> bool:
    if membership.status == "void":
        return False
    if membership.end_date is not None and released > membership.end_date:
        return False
    return membership.start_date <= released or membership_start_is_unknown(db, membership)
