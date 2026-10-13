from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.response import DomainError, success
from app.core.database import get_db
from app.core.security import current_user
from app.models import Comment, Report, SocialPost, SocialPostView, User
from app.modules.social_feed import service
from app.modules.social_feed.schemas import CommentCreate, ReplyCreate, ReportCreate

router = APIRouter(tags=["Idol Feed"])


def _post(db: Session, post_id: str) -> SocialPost:
    post = db.get(SocialPost, post_id)
    if post is None:
        raise DomainError("POST_NOT_FOUND", "动态不存在", 404)
    return post


def _comment(db: Session, comment_id: str) -> Comment:
    comment = db.get(Comment, comment_id)
    if comment is None or comment.is_deleted:
        raise DomainError("COMMENT_NOT_FOUND", "评论不存在", 404)
    return comment


def _feed_data(
    db: Session,
    idol_ids: str | None,
    group_ids: str | None,
    author_type: str | None,
    platform: str | None,
    cursor: str | None,
    limit: int,
) -> dict[str, object]:
    query = select(SocialPost)
    if idol_ids:
        query = query.where(SocialPost.idol_id.in_(idol_ids.split(",")))
    if group_ids:
        query = query.where(SocialPost.group_id.in_(group_ids.split(",")))
    if author_type:
        query = query.where(SocialPost.author_type == author_type)
    if platform:
        query = query.where(SocialPost.platform == platform)
    offset = max(0, int(cursor or 0))
    posts = db.scalars(
        query.order_by(SocialPost.posted_at.desc()).offset(offset).limit(limit + 1)
    ).all()
    page = posts[:limit]
    return {
        "items": [service.post_payload(db, post) for post in page],
        "next_cursor": str(offset + limit) if len(posts) > limit else None,
        "new_count": 5 if offset == 0 else 0,
        "unavailable_platforms": ["x"] if platform in {None, "x"} else [],
        "is_from_cache": platform == "x",
    }


@router.get("/idol-feed")
def get_feed(
    idol_ids: str | None = None,
    group_ids: str | None = None,
    author_type: str | None = None,
    platform: str | None = None,
    cursor: str | None = None,
    limit: int = Query(default=20, ge=1, le=50),
    db: Session = Depends(get_db),
) -> dict:
    return success(_feed_data(db, idol_ids, group_ids, author_type, platform, cursor, limit))


@router.post("/idol-feed/refresh")
def refresh_feed(payload: dict, db: Session = Depends(get_db)) -> dict:
    idol_ids = payload.get("idol_ids")
    joined = ",".join(idol_ids) if isinstance(idol_ids, list) else idol_ids
    data = _feed_data(
        db,
        joined,
        payload.get("group_ids"),
        payload.get("author_type"),
        payload.get("platform"),
        None,
        min(int(payload.get("limit", 20)), 50),
    )
    return success(data)


@router.get("/idol-feed/{post_id}")
def get_post(post_id: str, db: Session = Depends(get_db)) -> dict:
    return success(service.post_payload(db, _post(db, post_id)))


@router.put("/idol-feed/{post_id}/view")
def mark_viewed(
    post_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    _post(db, post_id)
    exists = db.scalar(
        select(SocialPostView).where(
            SocialPostView.user_id == user.id, SocialPostView.post_id == post_id
        )
    )
    if exists is None:
        db.add(SocialPostView(user_id=user.id, post_id=post_id))
        db.commit()
    return success({"viewed": True})


@router.put("/idol-feed/{post_id}/like")
def like_post(
    post_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.set_post_like(db, user, _post(db, post_id), True))


@router.delete("/idol-feed/{post_id}/like")
def unlike_post(
    post_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.set_post_like(db, user, _post(db, post_id), False))


@router.get("/idol-feed/{post_id}/comments")
def get_comments(
    post_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    _post(db, post_id)
    comments = db.scalars(
        select(Comment)
        .where(Comment.post_id == post_id, Comment.is_deleted.is_(False))
        .order_by(Comment.created_at)
    ).all()
    return success({"items": [service.comment_payload(db, item, user) for item in comments]})


@router.post("/idol-feed/{post_id}/comments")
def create_comment(
    post_id: str,
    payload: CommentCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    return success(service.add_comment(db, user, _post(db, post_id), payload.content))


@router.post("/idol-feed/{post_id}/comments/{comment_id}/replies")
def reply_comment(
    post_id: str,
    comment_id: str,
    payload: ReplyCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    parent = _comment(db, comment_id)
    if parent.post_id != post_id:
        raise DomainError("COMMENT_NOT_FOUND", "评论不存在", 404)
    return success(
        service.add_comment(
            db, user, _post(db, post_id), payload.content, parent, payload.reply_to_user_id
        )
    )


@router.delete("/comments/{comment_id}")
def delete_comment(
    comment_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    comment = _comment(db, comment_id)
    if comment.user_id != user.id:
        raise DomainError("COMMENT_DELETE_FORBIDDEN", "只能删除自己的评论", 403)
    comment.is_deleted = True
    db.commit()
    return success(message="评论已删除")


@router.put("/comments/{comment_id}/like")
def like_comment(
    comment_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.set_comment_like(db, user, _comment(db, comment_id), True))


@router.delete("/comments/{comment_id}/like")
def unlike_comment(
    comment_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
) -> dict:
    return success(service.set_comment_like(db, user, _comment(db, comment_id), False))


@router.post("/comments/{comment_id}/report")
def report_comment(
    comment_id: str,
    payload: ReportCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    comment = _comment(db, comment_id)
    exists = db.scalar(
        select(Report).where(
            Report.reporter_id == user.id,
            Report.target_type == "comment",
            Report.target_id == comment.id,
        )
    )
    if exists is None:
        db.add(
            Report(
                reporter_id=user.id,
                target_type="comment",
                target_id=comment.id,
                reason=payload.reason,
            )
        )
        db.commit()
    return success(message="举报已提交")
