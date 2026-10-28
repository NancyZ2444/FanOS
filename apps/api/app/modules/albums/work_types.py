"""V1.1 work boundaries shared by every editing endpoint."""

from app.common.response import DomainError


def validate_work(db, user, previous, doc, data):
    from .service import quota

    mode = previous.get("work_mode", "BOOK")
    if data.work_mode is not None and data.work_mode != mode:
        raise DomainError("ALBUM_MODE_IMMUTABLE", "作品类型创建后不可更换", 409)
    if data.card_view and data.card_view.default_mode != mode:
        raise DomainError("ALBUM_MODE_IMMUTABLE", "作品类型创建后不可更换", 409)
    if mode == "CARDS":
        if any(
            getattr(data, key) is not None
            for key in ("pages", "cover", "display_type", "visual_style")
        ):
            raise DomainError(
                "ALBUM_WRONG_WORK_FIELDS", "卡片作品没有封面画布、内页或单双面设置", 422
            )
        instances = doc.get("card_instances", [])
        if any(not s.get("card_id") for s in instances):
            raise DomainError("ALBUM_CARD_REQUIRED", "卡片实例必须关联官方小卡", 422)
        if len(instances) > max(
            len(previous.get("card_instances", [])), quota(db, user)["max_cards_per_work"]
        ):
            raise DomainError(
                "ALBUM_CARD_QUOTA_EXCEEDED", "已达到卡片作品容量，历史超额内容会保留", 409
            )
        if data.card_view and set(doc["card_view"]["card_order"]) != {s["id"] for s in instances}:
            raise DomainError("ALBUM_CARD_ORDER_INVALID", "顺序必须且只能包含全部卡片实例一次", 422)
    elif data.card_instances is not None:
        raise DomainError("ALBUM_WRONG_WORK_FIELDS", "相册作品的小卡只能放入封面或内页", 422)
