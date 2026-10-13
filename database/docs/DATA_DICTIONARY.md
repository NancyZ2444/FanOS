# Fan OS Phase 1 data dictionary

| Domain | Tables | Purpose |
| --- | --- | --- |
| Identity | `users`, `user_social_accounts` | Public profile, privacy, OAuth identity, role |
| Idol graph | `idols`, `groups`, `group_memberships`, `idol_official_accounts` | Current and historical group membership plus platform account binding |
| Preference | `user_idols` | Ordered multiple favorites; priority 0 is the primary favorite |
| Collection | `cards`, `user_collection_items`, `user_wishlist_items` | Official card catalog, owned quantity, independent wishlist |
| Personal assets | `card_albums`, `album_cards`, `profile_photos` | Digital albums and profile photo space |
| Relationships | `user_follows` | Directed follow graph; mutual follows are derived |
| Daily card | `daily_card_draws` | Server-side daily limit, idempotency and draw audit |
| Idol feed | `social_posts`, `social_post_views`, `social_post_likes` | Normalized third-party public content and user-scoped state |
| Comments | `comments`, `comment_likes`, `reports` | Two-level comments and moderation inputs |
| AI Scan | `scan_sessions`, `detected_cards`, `scan_candidates`, `scan_feedback` | Independent multi-card recognition results and unrecognized queue |
| Notification | `notification_settings` | Idol-feed aggregation and push preferences |
| Audit | `operation_logs` | Actor, target and before/after state for high-risk operations |
| Catalog operations | `catalog_operational_records` | Versions, source chains, batches, review input, companies and effective relationship periods; preserves existing entity IDs |
| Community (reserved) | `community_posts`, `community_post_media`, `community_comments`, `community_reactions`, `community_bookmarks` | Phase 2 user-generated content, separate from external Idol feed |
| Trust & safety (reserved) | `community_moderation_cases`, `user_blocks` | Community moderation and user safety controls |
| Delivery | `notifications`, `device_tokens` | Admin notifications now use the inbox; push device delivery remains reserved |
| Integration events | `outbox_events` | Transactional domain events; card image changes consumed by the index worker |

Public IDs are stable strings to remain compatible with the Flutter app. Foreign-key
relationships are normalized: groups never store member arrays, and users never store
a single `favorite_idol_id` column.

Company records use `kind=companies`, with the canonical display name in `data.name`.
Group and idol affiliations use `kind=company_relations`, an entity owner and
`data.company_id`; dates are inclusive. Legacy company backfill leaves dates empty,
sets `date_unknown=true`, and preserves `original_company` and its source. This denotes
current legacy attribution with unverified dates, not a verified historical period.
Admin `company_ids` is derived from effective relationships; omitted update selections
preserve existing attribution. Admin idol payloads expose complete `membership_history`
for group-scoped selections without discarding former members.

## Key constraints

- `user_idols(user_id, idol_id, relation_type)` is unique; `priority=0` marks the primary idol.
- `user_collection_items(user_id, card_id)` stores quantity instead of duplicate rows.
- `daily_card_draws(user_id, draw_date, draw_index)` enforces the daily sequence, while
  `(user_id, request_id)` makes retries idempotent.
- `social_posts(platform, original_post_id)` is the Worker upsert key.
- user views, post likes, comment likes, follows and wishlist rows all use composite
  uniqueness to make repeated PUT/DELETE calls safe.
- `scan_candidates(detected_card_id, card_id)` prevents duplicate AI candidates.
- `detected_cards.owned_added_at` records whether that physical region has already incremented
  Owned. `user_confirmed_card_id` alone can also represent a Wishlist/manual choice. A conditional
  update claims the region inside the collection transaction; replaying it does not add quantity.
- `community_reactions(user_id, target_type, target_id, reaction_type)` and
  `community_bookmarks(user_id, post_id)` make retries idempotent.
- `device_tokens(platform, token)` prevents duplicate push endpoints.
- Chat Room/Member/Message tables are intentionally absent: Phase 3 realtime data belongs to an
  independently deployable service and must not reuse community or external-feed comments.

All mutable business tables contain UTC `created_at` and `updated_at`. User-facing media
is represented by an object-storage URL; binary image data and model embeddings are not
stored in PostgreSQL rows.

## Admin Console extension · 2026-09-18

Migration: `d1f09a7c3e22`, following `a8e42c19f5d0`.

| Table / column | Purpose and constraint |
| --- | --- |
| `cards.status` | Indexed lifecycle state; migration preserves existing rows as `PUBLISHED`, new admin cards are `DRAFT` |
| `cards.admin_data` | JSON for source association, tags, flags, front/back source details, review note and operator |
| `cards.idol_id` | Nullable to support group cards; personal cards require a valid idol at service validation |
| `admin_content_metadata` | Unique `(entity_type, entity_id)`; status, supplemental JSON, operator and timestamps for catalog/operational content |
| `catalog_collections` | Named collection/other source entity with group foreign key, image, date and description |
| `card_image_versions` | Per-card, per-side version snapshots, source/copyright data, operator and timestamps |
| `admin_import_tasks` | Uploaded filename, validated JSON rows, field/row errors, task status, imported count and operator |

Lifecycle values are `DRAFT`, `PENDING`, `PUBLISHED`, `OFFLINE`, `REJECTED`, `ARCHIVED`.
Notifications additionally use `APPROVED` and `SENT`. Operational JSON records do not imply that
every entity supports every action; the service enforces allowed transitions and permissions.

Private provenance is excluded from public card serialization. API optimistic concurrency checks
`expected_updated_at` when saving an existing card. Import confirmation is idempotent per task.
Image updates create transactional Outbox records. The local index worker stores retry count,
last error and completion in the existing event fields.

A downgrade removes the new admin data and is not a production rollback strategy without a
backup. It explicitly refuses to continue when group cards without an idol exist. Fresh upgrade,
schema comparison, empty-schema downgrade and re-upgrade were verified on SQLite; PostgreSQL
execution remains a deployment check.

## Typed catalog imports · 2026-10-09

Migration `e2a10b8f4c63` follows `e22a811c4b03`. `admin_import_tasks.kind` is a non-null
`VARCHAR(30)` with default `cards`; values are cards, groups, idols, albums, events, collections,
merchandise. Historical imports remain card tasks. Confirmation dispatches by this persisted
type, not a client-supplied type. Confirmed JSON rows additionally contain `created_id`.
The downgrade refuses to erase the type while non-card tasks exist.
