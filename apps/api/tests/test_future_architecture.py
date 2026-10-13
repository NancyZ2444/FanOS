from __future__ import annotations

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.common.events import enqueue_outbox
from app.core.database import Base, SessionLocal
from app.future_models import OutboxEvent
from app.integrations.redis_cache import RedisKeySpace
from app.modules.chat_contract.schemas import ChatMessageType, SendMessageCommand
from app.modules.community.schemas import CommunityPostCreate, CommunitySubjectType


def test_reserved_tables_are_registered_without_new_routes(client) -> None:
    reserved = {
        "community_posts",
        "community_post_media",
        "community_comments",
        "community_reactions",
        "community_bookmarks",
        "community_moderation_cases",
        "user_blocks",
        "outbox_events",
        "notifications",
        "device_tokens",
    }
    assert reserved <= set(Base.metadata.tables)

    route_paths = {path for route in client.app.routes if (path := getattr(route, "path", None))}
    assert not any(path.startswith("/api/v1/community") for path in route_paths)
    assert not any(path.startswith("/api/v1/chat") for path in route_paths)


def test_outbox_event_joins_callers_transaction() -> None:
    with SessionLocal() as db:
        event = enqueue_outbox(
            db,
            event_type="collection.item.updated",
            aggregate_type="collection_item",
            aggregate_id="card-aria-01",
            payload={"quantity": 2},
        )
        db.commit()
        persisted = db.scalar(select(OutboxEvent).where(OutboxEvent.id == event.id))

    assert persisted is not None
    assert persisted.event_version == 1
    assert persisted.payload == {"quantity": 2}


def test_future_contracts_validate_before_service_implementation() -> None:
    post = CommunityPostCreate(
        content="今天的收藏",
        subject_type=CommunitySubjectType.idol,
        subject_id="idol-aria",
    )
    assert post.subject_id == "idol-aria"

    text = SendMessageCommand(
        room_id="room-1",
        client_message_id="ios-1001",
        message_type=ChatMessageType.text,
        content="你好",
    )
    assert text.message_type == ChatMessageType.text

    with pytest.raises(ValidationError):
        SendMessageCommand(
            room_id="room-1",
            client_message_id="ios-1002",
            message_type=ChatMessageType.text,
        )
    with pytest.raises(ValidationError):
        SendMessageCommand(
            room_id="room-1",
            client_message_id="ios-1003",
            message_type=ChatMessageType.post_share,
        )

    assert RedisKeySpace.community_feed("u1") == "fanos:v1:community:feed:u1"
    assert RedisKeySpace.chat_unread("u1", "r1") == "fanos:v1:chat:unread:u1:r1"
