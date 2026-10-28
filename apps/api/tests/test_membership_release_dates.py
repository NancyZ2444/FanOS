"""Membership recording dates must not masquerade as verified joining dates."""

from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import event, select
from test_admin_console import payload

from app.core.database import SessionLocal
from app.models import Card, GroupMembership, OperationLog
from app.modules.admin.catalog_extensions import CatalogRecord
from app.modules.admin.catalog_memberships import (
    create_undated_membership,
    membership_covers_release,
    membership_date_info,
    membership_start_is_unknown,
)
from app.modules.admin.catalog_service import validate_relations
from app.modules.admin.console_schemas import CardDraft

ROOT = "/api/v1/admin/console"


def legacy_membership(db, *, action="catalog.entity.save"):
    membership = db.scalar(
        select(GroupMembership).where(
            GroupMembership.idol_id == "idol-aria", GroupMembership.group_id == "group-lumina"
        )
    )
    recorded_at = datetime(2026, 10, 9, 3, 51, 33)
    membership.start_date = date(2026, 10, 9)
    membership.end_date = None
    membership.status = "active"
    membership.created_at = recorded_at
    membership.updated_at = recorded_at + timedelta(microseconds=1)
    is_import = action == "catalog.membership.import"
    log = OperationLog(
        actor_id="admin-demo",
        action=action,
        target_type="memberships" if is_import else "idols",
        target_id=membership.id if is_import else membership.idol_id,
        before=None,
        after={
            "id": membership.id if is_import else membership.idol_id,
            "group_id": membership.group_id,
            **(
                {"idol_id": membership.idol_id, "start_date": "2026-10-09"}
                if is_import
                else {"start_date": ""}
            ),
        },
        created_at=recorded_at + timedelta(milliseconds=10),
    )
    db.add(log)
    db.flush()
    return membership, log


@pytest.mark.parametrize("action", ["catalog.entity.save", "catalog.membership.import"])
def test_october_feedback_date_accepts_evidenced_automatic_recording_date(action):
    with SessionLocal() as db:
        membership, _ = legacy_membership(db, action=action)
        original = (membership.start_date, membership.updated_at)
        existing = db.get(Card, "card-aria-01")
        existing.release_date = ""
        draft = CardDraft(**payload(release_date="2026-10-01"))
        assert validate_relations(db, draft, complete=True, existing_card=existing) == []
        assert (membership.start_date, membership.updated_at) == original
        assert existing.release_date == ""  # Validation never publishes or updates the card.


@pytest.mark.parametrize(
    "case",
    ["no_audit", "wrong_group", "explicit_date", "relation_changed", "manual_history"],
)
def test_recording_day_alone_never_relaxes_real_or_unproven_membership(case):
    with SessionLocal() as db:
        membership, log = legacy_membership(db)
        if case == "no_audit":
            db.delete(log)
        elif case == "wrong_group":
            log.after = {**log.after, "group_id": "different-group"}
        elif case == "explicit_date":
            log.after = {**log.after, "start_date": "2026-10-09"}
        elif case == "relation_changed":
            membership.updated_at = membership.created_at + timedelta(days=1)
        else:
            db.add(
                CatalogRecord(
                    kind="memberships",
                    entity_type="idols",
                    entity_id=membership.idol_id,
                    data={"membership_id": membership.id, "start_date": "2026-10-09"},
                )
            )
        db.flush()
        assert not membership_start_is_unknown(db, membership)
        errors = validate_relations(db, CardDraft(**payload(release_date="2026-10-01")))
        assert any(error["field"] == "release_date" for error in errors)


def test_new_idol_group_selection_does_not_claim_a_joining_date(client, admin_headers):
    response = client.post(
        ROOT + "/entities/idols",
        headers=admin_headers,
        json={"name": "Undated member", "group_id": "group-lumina"},
    )
    assert response.status_code == 200, response.text
    idol_id = response.json()["data"]["id"]
    response = client.post(
        ROOT + "/cards",
        headers=admin_headers,
        json=payload(idol_id=idol_id, release_date="2023-10-01"),
    )
    assert response.status_code == 200, response.text
    with SessionLocal() as db:
        membership = db.scalar(select(GroupMembership).where(GroupMembership.idol_id == idol_id))
        record = db.scalar(
            select(CatalogRecord).where(
                CatalogRecord.kind == "memberships", CatalogRecord.entity_id == idol_id
            )
        )
        assert record.data["start_date"] == ""
        assert record.data["date_unknown"] is True
        assert membership_start_is_unknown(db, membership)


def test_unknown_start_keeps_end_date_and_explicit_history_restrictions():
    with SessionLocal() as db:
        membership = create_undated_membership(db, "group-aster", "idol-aria")
        membership.end_date = date(2025, 12, 31)
        membership.status = "former"
        db.flush()
        assert membership_covers_release(db, membership, date(2025, 10, 1))
        assert not membership_covers_release(db, membership, date(2026, 10, 1))
        record = db.scalar(
            select(CatalogRecord).where(
                CatalogRecord.kind == "memberships", CatalogRecord.entity_id == "idol-aria"
            )
        )
        # The public-profile/history editor supplies an actual period and replaces
        # the marker; stale marker metadata must not win over an explicit date.
        record.data = {**record.data, "start_date": "2025-06-01"}
        membership.start_date = date(2025, 6, 1)
        db.flush()
        assert not membership_start_is_unknown(db, membership)
        assert not membership_covers_release(db, membership, date(2025, 5, 31))
        assert membership_covers_release(db, membership, date(2025, 6, 1))
        membership.status = "void"
        assert not membership_covers_release(db, membership, date(2025, 10, 1))


def test_stale_automatic_marker_cannot_override_a_changed_start_date():
    with SessionLocal() as db:
        membership = create_undated_membership(db, "group-aster", "idol-aria")
        membership.start_date = date(2025, 6, 1)
        db.flush()
        assert not membership_start_is_unknown(db, membership)
        assert not membership_covers_release(db, membership, date(2025, 5, 31))


def test_explicit_multiple_periods_keep_rejoin_gap_closed():
    with SessionLocal() as db:
        membership, log = legacy_membership(db)
        db.delete(log)
        membership.start_date = date(2020, 1, 1)
        membership.end_date = date(2024, 12, 31)
        membership.status = "former"
        db.add(
            GroupMembership(
                group_id=membership.group_id,
                idol_id=membership.idol_id,
                start_date=date(2025, 6, 1),
                status="active",
            )
        )
        db.flush()
        for released in ["2023-10-01", "2025-10-01"]:
            assert validate_relations(db, CardDraft(**payload(release_date=released))) == []
        errors = validate_relations(db, CardDraft(**payload(release_date="2025-03-01")))
        assert any(error["field"] == "release_date" for error in errors)


def test_unknown_recording_date_is_not_offered_as_a_verified_joining_date(client, admin_headers):
    with SessionLocal() as db:
        membership, _ = legacy_membership(db)
        member_id = membership.id
        db.commit()
    response = client.get(ROOT + "/entities/groups/group-lumina/detail", headers=admin_headers)
    assert response.status_code == 200, response.text
    member = next(m for m in response.json()["data"]["memberships"] if m["id"] == member_id)
    assert member["start_date"] == "" and member["date_unknown"] is True
    response = client.get(ROOT + "/records/memberships?entity_id=idol-aria", headers=admin_headers)
    assert response.status_code == 200, response.text
    assert response.json()["data"]["items"][0]["data"]["start_date"] == ""
    response = client.get("/api/v1/catalog/profiles/idols/idol-aria")
    assert response.status_code == 200, response.text
    members = next(f for f in response.json()["data"]["fields"] if f["key"] == "memberships")
    assert members["current"][0]["start_date"] == ""


def test_member_date_display_batches_provenance_queries():
    with SessionLocal() as db:
        membership, _ = legacy_membership(db)
        others = list(db.scalars(select(GroupMembership)))
        statements = []

        def capture(_conn, _cursor, statement, _parameters, _context, _executemany):
            statements.append(statement)

        event.listen(db.bind, "before_cursor_execute", capture)
        try:
            result = membership_date_info(db, others)
        finally:
            event.remove(db.bind, "before_cursor_execute", capture)
        assert result[membership.id]["date_unknown"] is True
        assert len(statements) == 2


def test_confirming_actual_history_cannot_exclude_previously_accepted_card():
    from app.common.response import DomainError
    from app.modules.catalog.profiles import apply_relations

    with SessionLocal() as db:
        membership, _ = legacy_membership(db)
        card = db.get(Card, "card-aria-01")
        card.release_date = "2026-10-01"
        db.flush()
        with pytest.raises(DomainError) as failure:
            apply_relations(
                db,
                "idols",
                "idol-aria",
                "memberships",
                [
                    {
                        "operation": "UPDATE",
                        "id": membership.id,
                        "data": {
                            "target_id": "group-lumina",
                            "start_date": "2026-10-09",
                            "end_date": "",
                            "status": "active",
                        },
                    }
                ],
            )
        assert failure.value.error_code == "HISTORY_PROTECTED"
