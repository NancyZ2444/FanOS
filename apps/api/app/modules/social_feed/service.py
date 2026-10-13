from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.admin_models import ContentMetadata
from app.common.response import DomainError
from app.models import (
    Comment,
    CommentLike,
    Group,
    Idol,
    SocialPost,
    SocialPostLike,
    User,
)


def post_payload(db: Session, post: SocialPost) -> dict[str, object]:
    idol = db.get(Idol, post.idol_id) if post.idol_id else None
    group = db.get(Group, post.group_id) if post.group_id else None
    like_count = post.base_like_count + (
        db.scalar(
            select(func.count())
            .select_from(SocialPostLike)
            .where(SocialPostLike.post_id == post.id)
        )
        or 0
    )
    comment_count = post.base_comment_count + (
        db.scalar(
            select(func.count())
            .select_from(Comment)
            .where(Comment.post_id == post.id, Comment.is_deleted.is_(False))
        )
        or 0
    )
    author_type = post.author_type
    author_id = group.id if author_type == "group" and group else idol.id if idol else None
    metadata = (
        db.scalar(
            select(ContentMetadata).where(
                ContentMetadata.entity_type == ("groups" if author_type == "group" else "idols"),
                ContentMetadata.entity_id == author_id,
                ContentMetadata.status == "PUBLISHED",
            )
        )
        if author_id
        else None
    )
    return {
        "id": post.id,
        "platform": post.platform,
        "original_post_id": post.original_post_id,
        "author_type": author_type,
        "idol_image_url": (metadata.data or {}).get("image_url") if metadata else None,
        "idol_id": idol.id if idol else "",
        "idol_name": group.name + " Official"
        if author_type == "group" and group
        else idol.name
        if idol
        else "Official",
        "idol_initials": group.name[:2]
        if author_type == "group" and group
        else idol.initials
        if idol
        else "OS",
        "idol_color_start": group.color_start
        if author_type == "group" and group
        else idol.color_start
        if idol
        else 0xFFBBA9FF,
        "idol_color_end": group.color_end
        if author_type == "group" and group
        else idol.color_end
        if idol
        else 0xFF5A58A4,
        "group_id": group.id if group else "",
        "group_name": group.name if group else "",
        "post_time": post.posted_at.isoformat(),
        "content": post.content if post.is_available else "",
        "media": post.media if post.is_available else [],
        "original_url": post.original_url,
        "deep_link_url": post.deep_link_url,
        "fetch_time": post.fetched_at.isoformat(),
        "relation": post.relation,
        "is_available": post.is_available,
        "like_count": like_count,
        "comment_count": comment_count,
        "share_count": post.share_count,
    }


def comment_payload(db: Session, comment: Comment, viewer: User) -> dict[str, object]:
    author = db.get(User, comment.user_id)
    reply_to = db.get(User, comment.reply_to_user_id) if comment.reply_to_user_id else None
    like_count = (
        db.scalar(
            select(func.count())
            .select_from(CommentLike)
            .where(CommentLike.comment_id == comment.id)
        )
        or 0
    )
    return {
        "id": comment.id,
        "post_id": comment.post_id,
        "user_id": comment.user_id,
        "user_name": author.display_name if author else "Fan OS 用户",
        "content": comment.content if not comment.is_deleted else "该评论已删除",
        "created_at": comment.created_at.isoformat(),
        "parent_id": comment.parent_id,
        "reply_to_name": reply_to.display_name if reply_to else None,
        "like_count": like_count,
        "is_mine": comment.user_id == viewer.id,
    }


def add_comment(
    db: Session,
    user: User,
    post: SocialPost,
    content: str,
    parent: Comment | None = None,
    reply_to_user_id: str | None = None,
) -> dict[str, object]:
    if not post.is_available:
        raise DomainError("POST_UNAVAILABLE", "原动态已删除或不可访问", 410)
    root_parent_id = parent.parent_id or parent.id if parent else None
    comment = Comment(
        post_id=post.id,
        user_id=user.id,
        content=content.strip(),
        parent_id=root_parent_id,
        reply_to_user_id=reply_to_user_id or (parent.user_id if parent else None),
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return comment_payload(db, comment, user)


def set_post_like(db: Session, user: User, post: SocialPost, liked: bool) -> dict[str, object]:
    row = db.scalar(
        select(SocialPostLike).where(
            SocialPostLike.user_id == user.id, SocialPostLike.post_id == post.id
        )
    )
    if liked and row is None:
        db.add(SocialPostLike(user_id=user.id, post_id=post.id))
    elif not liked and row:
        db.delete(row)
    db.commit()
    return {"liked": liked, "like_count": post_payload(db, post)["like_count"]}


def set_comment_like(db: Session, user: User, comment: Comment, liked: bool) -> dict[str, object]:
    row = db.scalar(
        select(CommentLike).where(
            CommentLike.user_id == user.id, CommentLike.comment_id == comment.id
        )
    )
    if liked and row is None:
        db.add(CommentLike(user_id=user.id, comment_id=comment.id))
    elif not liked and row:
        db.delete(row)
    db.commit()
    count = (
        db.scalar(
            select(func.count())
            .select_from(CommentLike)
            .where(CommentLike.comment_id == comment.id)
        )
        or 0
    )
    return {"liked": liked, "like_count": count}
