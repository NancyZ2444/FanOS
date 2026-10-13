"""Preview or transactionally remove exact seed catalog IDs and linked records."""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sqlalchemy import MetaData, and_, delete, or_, select

from app.core.database import engine
from app.seed import CARDS, CATALOG_ALBUMS, CATALOG_EVENTS, CATALOG_MERCHANDISE, GROUPS, IDOLS

parser = argparse.ArgumentParser()
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
roots = {
    "groups": {r[0] for r in GROUPS},
    "idols": {r[0] for r in IDOLS},
    "cards": {r[0] for r in CARDS},
    "catalog_albums": {r[0] for r in CATALOG_ALBUMS},
    "catalog_events": {r[0] for r in CATALOG_EVENTS},
    "catalog_merchandise": {r[0] for r in CATALOG_MERCHANDISE},
    "catalog_others": {r[0] for r in CATALOG_MERCHANDISE},
    "social_posts": {f"feed-{i}" for i in range(1, 35)},
}
with engine.connect() as conn:
    transaction = conn.begin()
    try:
        meta = MetaData()
        meta.reflect(bind=conn)
        selected = {name: set() for name in meta.tables}
        for name, ids in roots.items():
            if name in meta.tables:
                table = meta.tables[name]
                selected[name].update(
                    tuple(row)
                    for row in conn.execute(
                        select(*table.primary_key.columns).where(table.c.id.in_(ids))
                    )
                )
        if "social_posts" in meta.tables:
            table = meta.tables["social_posts"]
            selected["social_posts"].update(
                tuple(row)
                for row in conn.execute(
                    select(*table.primary_key.columns).where(
                        and_(
                            table.c.original_post_id.like("mock-%"),
                            table.c.idol_id == "idol-aria",
                            table.c.group_id == "group-lumina",
                        )
                    )
                )
            )
        changed = True
        while changed:
            changed = False
            for name, table in meta.tables.items():
                clauses = []
                for fk in table.foreign_keys:
                    parent = fk.column.table
                    if selected[parent.name]:
                        pk = list(parent.primary_key.columns)
                        if len(pk) != 1 or pk[0].name != fk.column.name:
                            raise RuntimeError("Unsupported foreign key; no data deleted")
                        clauses.append(fk.parent.in_([row[0] for row in selected[parent.name]]))
                if "entity_id" in table.c and "entity_type" in table.c:
                    scopes = {
                        "groups": "groups",
                        "idols": "idols",
                        "cards": "cards",
                        "albums": "catalog_albums",
                        "events": "catalog_events",
                        "others": "catalog_others",
                        "merchandise": "catalog_merchandise",
                    }
                    for kind, parent in scopes.items():
                        if selected.get(parent):
                            clauses.append(
                                and_(
                                    table.c.entity_type == kind,
                                    table.c.entity_id.in_([row[0] for row in selected[parent]]),
                                )
                            )
                if not clauses:
                    continue
                pk = list(table.primary_key.columns)
                rows = {tuple(row) for row in conn.execute(select(*pk).where(or_(*clauses)))}
                new = rows - selected[name]
                if name in roots and new:
                    raise RuntimeError(
                        f"{name}: non-demo records reference demo data; no data deleted"
                    )
                if new:
                    selected[name].update(new)
                    changed = True
        for name, rows in selected.items():
            if rows:
                print(f"{name}: {len(rows)}")
        if not args.apply:
            transaction.rollback()
            print(
                "PREVIEW ONLY: no data deleted. "
                "Linked collection/scan/comment records are included."
            )
        else:
            # Repeated passes handle self-referencing event/comment trees.
            pending = {name: set(rows) for name, rows in selected.items() if rows}
            while pending:
                progress = False
                for name in list(pending):
                    table = meta.tables[name]
                    for row in list(pending[name]):
                        try:
                            with conn.begin_nested():
                                conn.execute(
                                    delete(table).where(
                                        and_(
                                            *(
                                                c == value
                                                for c, value in zip(
                                                    table.primary_key.columns, row, strict=False
                                                )
                                            )
                                        )
                                    )
                                )
                            pending[name].remove(row)
                            progress = True
                        except Exception as error:
                            if "IntegrityError" not in type(error).__name__:
                                raise
                    if not pending[name]:
                        del pending[name]
                if not progress:
                    raise RuntimeError("Unresolved references; all deletions rolled back")
            transaction.commit()
            print(
                "Demo catalog and linked records removed. "
                "Users, admin, uploaded files and taxonomy marker retained."
            )
    except Exception:
        if transaction.is_active:
            transaction.rollback()
        raise
