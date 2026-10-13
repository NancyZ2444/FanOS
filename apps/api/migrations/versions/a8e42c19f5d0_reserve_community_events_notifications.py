"""reserve community, delivery, and integration-event boundaries

Revision ID: a8e42c19f5d0
Revises: 7c31e9a8d4b2
Create Date: 2026-09-16 18:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a8e42c19f5d0"
down_revision: str | None = "7c31e9a8d4b2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _timestamps() -> tuple[sa.Column, sa.Column]:
    return (
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def upgrade() -> None:
    op.create_table(
        "community_posts",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("author_id", sa.String(length=64), nullable=False),
        sa.Column("subject_type", sa.String(length=30), nullable=True),
        sa.Column("subject_id", sa.String(length=64), nullable=True),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("visibility", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("view_count", sa.Integer(), nullable=False),
        sa.Column("reaction_count", sa.Integer(), nullable=False),
        sa.Column("comment_count", sa.Integer(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["author_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "author_id",
        "subject_type",
        "subject_id",
        "visibility",
        "status",
        "published_at",
    ):
        op.create_index(f"ix_community_posts_{column}", "community_posts", [column])

    op.create_table(
        "community_post_media",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("post_id", sa.String(length=64), nullable=False),
        sa.Column("media_type", sa.String(length=20), nullable=False),
        sa.Column("url", sa.String(length=800), nullable=False),
        sa.Column("cover_url", sa.String(length=800), nullable=True),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("moderation_status", sa.String(length=30), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["post_id"], ["community_posts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_community_post_media_post_id", "community_post_media", ["post_id"])
    op.create_index(
        "ix_community_post_media_moderation_status",
        "community_post_media",
        ["moderation_status"],
    )

    op.create_table(
        "community_comments",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("post_id", sa.String(length=64), nullable=False),
        sa.Column("author_id", sa.String(length=64), nullable=False),
        sa.Column("parent_id", sa.String(length=64), nullable=True),
        sa.Column("reply_to_user_id", sa.String(length=64), nullable=True),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["author_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["parent_id"], ["community_comments.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["post_id"], ["community_posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reply_to_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("post_id", "author_id", "parent_id", "status"):
        op.create_index(f"ix_community_comments_{column}", "community_comments", [column])

    op.create_table(
        "community_reactions",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("target_type", sa.String(length=20), nullable=False),
        sa.Column("target_id", sa.String(length=64), nullable=False),
        sa.Column("reaction_type", sa.String(length=20), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "target_type", "target_id", "reaction_type"),
    )
    for column in ("user_id", "target_type", "target_id"):
        op.create_index(f"ix_community_reactions_{column}", "community_reactions", [column])

    op.create_table(
        "community_bookmarks",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("post_id", sa.String(length=64), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["post_id"], ["community_posts.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "post_id"),
    )
    op.create_index("ix_community_bookmarks_user_id", "community_bookmarks", ["user_id"])
    op.create_index("ix_community_bookmarks_post_id", "community_bookmarks", ["post_id"])

    op.create_table(
        "community_moderation_cases",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("reporter_id", sa.String(length=64), nullable=True),
        sa.Column("target_type", sa.String(length=30), nullable=False),
        sa.Column("target_id", sa.String(length=64), nullable=False),
        sa.Column("reason", sa.String(length=100), nullable=False),
        sa.Column("details", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=30), nullable=False),
        sa.Column("reviewer_id", sa.String(length=64), nullable=True),
        sa.Column("resolution", sa.Text(), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["reporter_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["reviewer_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("reporter_id", "target_type", "target_id", "status"):
        op.create_index(
            f"ix_community_moderation_cases_{column}",
            "community_moderation_cases",
            [column],
        )

    op.create_table(
        "user_blocks",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("blocker_id", sa.String(length=64), nullable=False),
        sa.Column("blocked_id", sa.String(length=64), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["blocked_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocker_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("blocker_id", "blocked_id"),
    )
    op.create_index("ix_user_blocks_blocker_id", "user_blocks", ["blocker_id"])
    op.create_index("ix_user_blocks_blocked_id", "user_blocks", ["blocked_id"])

    op.create_table(
        "outbox_events",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("event_type", sa.String(length=120), nullable=False),
        sa.Column("event_version", sa.Integer(), nullable=False),
        sa.Column("aggregate_type", sa.String(length=60), nullable=False),
        sa.Column("aggregate_id", sa.String(length=64), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("publish_attempts", sa.Integer(), nullable=False),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in (
        "event_type",
        "aggregate_type",
        "aggregate_id",
        "occurred_at",
        "published_at",
    ):
        op.create_index(f"ix_outbox_events_{column}", "outbox_events", [column])

    op.create_table(
        "notifications",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("category", sa.String(length=40), nullable=False),
        sa.Column("source_type", sa.String(length=40), nullable=True),
        sa.Column("source_id", sa.String(length=64), nullable=True),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("body", sa.String(length=500), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    for column in ("user_id", "category", "source_type", "source_id", "read_at"):
        op.create_index(f"ix_notifications_{column}", "notifications", [column])

    op.create_table(
        "device_tokens",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("platform", sa.String(length=20), nullable=False),
        sa.Column("token", sa.String(length=500), nullable=False),
        sa.Column("app_version", sa.String(length=40), nullable=True),
        sa.Column("locale", sa.String(length=20), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("platform", "token"),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("ix_device_tokens_platform", "device_tokens", ["platform"])
    op.create_index("ix_device_tokens_is_active", "device_tokens", ["is_active"])


def downgrade() -> None:
    for table in (
        "device_tokens",
        "notifications",
        "outbox_events",
        "user_blocks",
        "community_moderation_cases",
        "community_bookmarks",
        "community_reactions",
        "community_comments",
        "community_post_media",
        "community_posts",
    ):
        op.drop_table(table)
