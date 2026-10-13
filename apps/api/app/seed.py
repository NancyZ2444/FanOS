from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    Card,
    CardAlbum,
    CatalogAlbum,
    CatalogEvent,
    CatalogMerchandise,
    Comment,
    Group,
    GroupMembership,
    Idol,
    NotificationSetting,
    SocialPost,
    User,
    UserCollectionItem,
    UserFollow,
    UserIdol,
    UserWishlistItem,
)

GROUP_DETAILS = {
    "group-lumina": ("2024.01.18", "Korea"),
    "group-aster": ("2025.03.21", "Korea"),
    "group-nova": ("2024.09.06", "Korea"),
}

LOCALIZED_NAMES = {
    "group-lumina": ("LUMINA", "루미나", "露米娜"),
    "group-aster": ("ASTER", "아스터", "星芒"),
    "group-nova": ("NOVA", "노바", "新星"),
    "idol-aria": ("Aria", "아리아", "艾莉娅"),
    "idol-lin": ("Lin", "린", "琳"),
    "idol-mina": ("Mina", "미나", "米娜"),
    "idol-ren": ("Ren", "렌", "任"),
    "idol-yuna": ("Yuna", "유나", "尤娜"),
    "idol-sora": ("Sora", "소라", "空"),
    "album-starlit": ("Starlit", "스타릿", "星光"),
    "album-blue-hour": ("Blue Hour", "블루 아워", "蓝色时刻"),
    "album-bloom": ("Bloom", "블룸", "绽放"),
    "album-afterglow": ("Afterglow", "애프터글로우", "余晖"),
    "event-starlit-seoul": (
        "Starlit Fansign · Seoul",
        "스타릿 팬사인회 · 서울",
        "星光签售会 · 首尔",
    ),
    "event-blue-hour-popup": ("Blue Hour Pop-up", "블루 아워 팝업", "蓝色时刻快闪店"),
    "event-bloom-tokyo": ("Bloom Fansign · Tokyo", "블룸 팬사인회 · 도쿄", "绽放签售会 · 东京"),
    "event-afterglow-tour": ("Afterglow Live Tour", "애프터글로우 라이브 투어", "余晖巡演"),
    "event-afterglow-shanghai": (
        "Afterglow Tour · Shanghai",
        "애프터글로우 투어 · 상하이",
        "余晖巡演 · 上海",
    ),
    "merch-starlit-lightstick": ("Starlit Mini Light", "스타릿 미니 라이트", "星光迷你应援灯"),
    "merch-bloom-bag": ("Bloom Flower Bag", "블룸 플라워 백", "绽放花朵收纳袋"),
    "merch-afterglow-shirt": (
        "Afterglow Tour T-shirt",
        "애프터글로우 투어 티셔츠",
        "余晖巡演 T 恤",
    ),
    "card-aria-01": ("Aria · Starlit POB", "아리아 · 스타릿 POB", "艾莉娅 · 星光特典卡"),
    "card-lin-01": ("Lin · Starlit Album", "린 · 스타릿 앨범 카드", "琳 · 星光专辑卡"),
    "card-aria-02": ("Aria · Blue Hour", "아리아 · 블루 아워", "艾莉娅 · 蓝色时刻"),
    "card-mina-01": ("Mina · Bloom", "미나 · 블룸", "米娜 · 绽放"),
    "card-yuna-01": ("Yuna · Bloom POB", "유나 · 블룸 POB", "尤娜 · 绽放特典卡"),
    "card-ren-01": ("Ren · Afterglow", "렌 · 애프터글로우", "任 · 余晖"),
    "card-sora-01": ("Sora · Afterglow", "소라 · 애프터글로우", "空 · 余晖"),
}

IDOL_DETAILS = {
    "idol-aria": (
        "North Star Studio",
        "2001.04.11",
        "Korea",
        "Leader · Main Vocal",
        [{"period": "2024.01 — 至今", "title": "LUMINA", "subtitle": "队长 / 主唱"}],
    ),
    "idol-lin": (
        "North Star Studio",
        "2002.09.08",
        "China",
        "Main Dancer · Vocal",
        [{"period": "2024.01 — 至今", "title": "LUMINA", "subtitle": "主舞 / 副唱"}],
    ),
    "idol-mina": (
        "Orbit Entertainment",
        "2003.02.17",
        "Japan",
        "Main Vocal",
        [{"period": "2025.03 — 至今", "title": "ASTER", "subtitle": "主唱"}],
    ),
    "idol-yuna": (
        "Orbit Entertainment",
        "2002.07.26",
        "Japan",
        "Leader · Performer",
        [{"period": "2025.03 — 至今", "title": "ASTER", "subtitle": "队长 / 表演"}],
    ),
    "idol-ren": (
        "Blue Hour Records",
        "2000.12.03",
        "China",
        "Producer · Vocal",
        [{"period": "2024.09 — 至今", "title": "NOVA", "subtitle": "制作人 / 主唱"}],
    ),
    "idol-sora": (
        "Blue Hour Records",
        "2001.06.15",
        "Korea",
        "Performer · Rap",
        [{"period": "2024.09 — 至今", "title": "NOVA", "subtitle": "表演 / Rap"}],
    ),
}

CATALOG_ALBUMS = [
    (
        "album-starlit",
        "Starlit",
        "LUMINA",
        "group-lumina",
        "2026.08.16",
        "Mini Album",
        ["Moon Ver.", "Dawn Ver."],
        "以夜空与晨光为线索，记录相遇之后逐渐汇聚的微光。",
        0xFFCFC4FF,
        0xFF6258B3,
    ),
    (
        "album-blue-hour",
        "Blue Hour",
        "LUMINA",
        "group-lumina",
        "2026.06.21",
        "Digital Single",
        ["City Ver."],
        "在城市入夜之前，收藏短暂却清晰的蓝色时刻。",
        0xFFA9C8FF,
        0xFF4C4B91,
    ),
    (
        "album-bloom",
        "Bloom",
        "ASTER",
        "group-aster",
        "2026.07.02",
        "Single Album",
        ["Petal Ver.", "Garden Ver."],
        "从种子到盛放，呈现属于 ASTER 的夏日能量。",
        0xFFFFCAD6,
        0xFFC35C82,
    ),
    (
        "album-afterglow",
        "Afterglow",
        "NOVA",
        "group-nova",
        "2026.04.10",
        "Full Album",
        ["Seoul Ver.", "Shanghai Ver."],
        "在旅途落幕后，继续追寻留在时间里的光。",
        0xFFB8DCD6,
        0xFF24596B,
    ),
]

CATALOG_EVENTS = [
    (
        "event-starlit-seoul",
        "Starlit Fansign · Seoul",
        "LUMINA",
        "group-lumina",
        "Fan Sign",
        "2026.08.16",
        "Korea",
        "Seoul",
        "North Star Hall",
        None,
        False,
        "Starlit 发行纪念线下签售活动。",
        0xFFD7CEFF,
        0xFF655CB5,
    ),
    (
        "event-blue-hour-popup",
        "Blue Hour Pop-up",
        "LUMINA",
        "group-lumina",
        "Pop-up",
        "2026.06.21",
        "China",
        "Shanghai",
        "Riverfront Space",
        None,
        False,
        "限时视觉展陈、专辑体验与城市限定周边。",
        0xFFBBD6FF,
        0xFF52519A,
    ),
    (
        "event-bloom-tokyo",
        "Bloom Fansign · Tokyo",
        "ASTER",
        "group-aster",
        "Fan Sign",
        "2026.07.05",
        "Japan",
        "Tokyo",
        "Orbit Theater",
        None,
        False,
        "Bloom 日本发行纪念签售。",
        0xFFFFD7E1,
        0xFFB95378,
    ),
    (
        "event-afterglow-tour",
        "Afterglow Live Tour",
        "NOVA",
        "group-nova",
        "Tour",
        "2026.04.26",
        "Asia",
        "Seoul · Shanghai",
        "Multiple Venues",
        None,
        False,
        "NOVA 首次亚洲巡演，包含 Seoul 与 Shanghai 场次。",
        0xFFADD9D0,
        0xFF23566A,
    ),
    (
        "event-afterglow-shanghai",
        "Afterglow Tour · Shanghai",
        "NOVA",
        "group-nova",
        "Concert",
        "2026.05.18",
        "China",
        "Shanghai",
        "Starlight Arena",
        "event-afterglow-tour",
        False,
        "Afterglow Live Tour 上海限定场次。",
        0xFFFFD8A8,
        0xFF8D5A4A,
    ),
]

CATALOG_MERCHANDISE = [
    (
        "merch-starlit-lightstick",
        "Starlit Mini Light",
        "LUMINA",
        "group-lumina",
        "Light",
        "Starlit",
        "2026.08.16",
        "Global",
        "Starlit 系列迷你应援灯。",
        0xFFD7CEFF,
        0xFF655CB5,
    ),
    (
        "merch-bloom-bag",
        "Bloom Flower Bag",
        "ASTER",
        "group-aster",
        "Bag",
        "Bloom",
        "2026.07.02",
        "Japan",
        "Bloom 花瓣概念收纳袋。",
        0xFFFFD7E1,
        0xFFB95378,
    ),
    (
        "merch-afterglow-shirt",
        "Afterglow Tour T-shirt",
        "NOVA",
        "group-nova",
        "Apparel",
        "Afterglow Tour",
        "2026.04.26",
        "Asia",
        "Afterglow 巡演官方服饰。",
        0xFFADD9D0,
        0xFF23566A,
    ),
]


def _seed_catalog_discovery(db: Session) -> None:
    for group_id, (debut_date, region) in GROUP_DETAILS.items():
        group = db.get(Group, group_id)
        if group is not None:
            group.debut_date = debut_date
            group.region = region
            group.name_en, group.name_ko, group.name_translated = LOCALIZED_NAMES[group_id]

    for idol_id, details in IDOL_DETAILS.items():
        idol = db.get(Idol, idol_id)
        if idol is not None:
            idol.company = details[0]
            idol.birth_date = details[1]
            idol.region = details[2]
            idol.role = details[3]
            idol.careers = details[4]
            idol.name_en, idol.name_ko, idol.name_translated = LOCALIZED_NAMES[idol_id]

    for item in CATALOG_ALBUMS:
        album = db.get(CatalogAlbum, item[0])
        if album is None:
            album = CatalogAlbum(
                id=item[0],
                name=item[1],
                artist_name=item[2],
                group_id=item[3],
                release_date=item[4],
                album_type=item[5],
                versions=item[6],
                description=item[7],
                color_start=item[8],
                color_end=item[9],
            )
            db.add(album)
        album.name_en, album.name_ko, album.name_translated = LOCALIZED_NAMES[item[0]]
    for item in CATALOG_EVENTS:
        event = db.get(CatalogEvent, item[0])
        if event is None:
            event = CatalogEvent(
                id=item[0],
                name=item[1],
                artist_name=item[2],
                group_id=item[3],
                event_type=item[4],
                start_date=item[5],
                region=item[6],
                city=item[7],
                venue=item[8],
                parent_event_id=item[9],
                is_online=item[10],
                description=item[11],
                color_start=item[12],
                color_end=item[13],
            )
            db.add(event)
        event.name_en, event.name_ko, event.name_translated = LOCALIZED_NAMES[item[0]]
        db.flush()
    for item in CATALOG_MERCHANDISE:
        merchandise = db.get(CatalogMerchandise, item[0])
        if merchandise is None:
            merchandise = CatalogMerchandise(
                id=item[0],
                name=item[1],
                artist_name=item[2],
                group_id=item[3],
                type=item[4],
                source=item[5],
                release_date=item[6],
                region=item[7],
                description=item[8],
                color_start=item[9],
                color_end=item[10],
            )
            db.add(merchandise)
        (
            merchandise.name_en,
            merchandise.name_ko,
            merchandise.name_translated,
        ) = LOCALIZED_NAMES[item[0]]

    for card_id, localized in LOCALIZED_NAMES.items():
        if not card_id.startswith("card-"):
            continue
        card = db.get(Card, card_id)
        if card is not None:
            card.title_en, card.title_ko, card.title_translated = localized


IDOLS = [
    ("idol-aria", "Aria", "AR", "温柔而坚定的主唱，用音乐记录每一次相遇。", 0xFFB79BFF, 0xFF5B5FC7),
    ("idol-lin", "Lin", "LN", "舞台表现力出众的领舞，喜欢摄影与旅行。", 0xFF91D7F2, 0xFF3977A8),
    ("idol-mina", "Mina", "MI", "以清澈声线和明亮能量被大家记住。", 0xFFFFB7C8, 0xFFB84670),
    ("idol-ren", "Ren", "RN", "创作型歌手，在每张作品里探索新的世界。", 0xFFFFD08A, 0xFFBD6A45),
    ("idol-yuna", "Yuna", "YU", "来自海边城市的全能艺人。", 0xFF9FE0CE, 0xFF2D8676),
    ("idol-sora", "Sora", "SO", "把想象力带上舞台的表演者。", 0xFFA8B6FF, 0xFF4852A8),
]

GROUPS = [
    (
        "group-lumina",
        "LUMINA",
        "North Star Studio",
        "以“微光汇聚成银河”为概念的女子组合。",
        0xFF191D3A,
        0xFF6D63C7,
    ),
    (
        "group-aster",
        "ASTER",
        "Orbit Entertainment",
        "明快、多彩，持续尝试跨风格表达。",
        0xFF71345A,
        0xFFF09AAE,
    ),
    (
        "group-nova",
        "NOVA",
        "Blue Hour Records",
        "围绕时间与成长创作的双人组合。",
        0xFF1D4C61,
        0xFF70C6B7,
    ),
]

MEMBERS = {
    "group-lumina": ["idol-aria", "idol-lin"],
    "group-aster": ["idol-mina", "idol-yuna"],
    "group-nova": ["idol-ren", "idol-sora"],
}

CARDS = [
    (
        "card-aria-01",
        "Aria · Starlit POB",
        "idol-aria",
        "group-lumina",
        "Starlit · Seoul Fansign",
        "POB",
        "Moon Ver.",
        "2026.08.16",
        "Korea",
        0xFFCEC0FF,
        0xFF665EA8,
    ),
    (
        "card-lin-01",
        "Lin · Starlit Album",
        "idol-lin",
        "group-lumina",
        "Starlit",
        "Album Card",
        "Dawn Ver.",
        "2026.08.16",
        "Global",
        0xFFB9E8F7,
        0xFF467FAC,
    ),
    (
        "card-aria-02",
        "Aria · Blue Hour",
        "idol-aria",
        "group-lumina",
        "Blue Hour Pop-up",
        "Lucky Draw",
        "City Ver.",
        "2026.06.21",
        "China",
        0xFFA9C8FF,
        0xFF4C4B91,
    ),
    (
        "card-mina-01",
        "Mina · Bloom",
        "idol-mina",
        "group-aster",
        "Bloom",
        "Album Card",
        "Petal Ver.",
        "2026.07.02",
        "Japan",
        0xFFFFCAD6,
        0xFFC35C82,
    ),
    (
        "card-yuna-01",
        "Yuna · Bloom POB",
        "idol-yuna",
        "group-aster",
        "Bloom · Tokyo Fansign",
        "POB",
        "Petal Ver.",
        "2026.07.05",
        "Japan",
        0xFFBCEBDD,
        0xFF398979,
    ),
    (
        "card-ren-01",
        "Ren · Afterglow",
        "idol-ren",
        "group-nova",
        "Afterglow Tour",
        "Tour Limited",
        "Shanghai Ver.",
        "2026.05.18",
        "China",
        0xFFFFD8A8,
        0xFFBB7458,
    ),
    (
        "card-sora-01",
        "Sora · Afterglow",
        "idol-sora",
        "group-nova",
        "Afterglow Tour",
        "Tour Limited",
        "Seoul Ver.",
        "2026.04.26",
        "Korea",
        0xFFC9D1FF,
        0xFF4F5AA7,
    ),
]


def seed_database(db: Session) -> None:
    from app.modules.catalog.taxonomy_upgrade import migrate_taxonomy

    if db.scalar(select(func.count()).select_from(User)):
        _seed_catalog_discovery(db)
        migrate_taxonomy(db)
        db.commit()
        return

    users = [
        User(
            id="current-user",
            phone="13800000000",
            display_name="星河收藏家",
            bio="把每一次心动，都好好收藏。",
            level=12,
            experience=3280,
            next_level_experience=4000,
        ),
        User(
            id="user-luna",
            phone=None,
            display_name="月光收藏家",
            bio="记录每一次舞台和拆卡时刻。",
            level=16,
            experience=4620,
            next_level_experience=5200,
            weibo_visible=True,
        ),
        User(
            id="user-mint",
            phone=None,
            display_name="薄荷汽水",
            bio="ASTER 双人推，偶尔分享线下活动记录。",
            level=8,
            experience=1680,
            next_level_experience=2000,
            likes_visible=False,
            photos_visible=False,
            following_list_visible=False,
        ),
        User(
            id="admin-demo", phone="13900000000", display_name="Fan OS 运营", role="admin", level=1
        ),
    ]
    db.add_all(users)
    db.flush()
    db.add_all(
        [
            Group(
                id=i[0], name=i[1], company=i[2], description=i[3], color_start=i[4], color_end=i[5]
            )
            for i in GROUPS
        ]
    )
    db.flush()
    db.add_all(
        [
            Idol(id=i[0], name=i[1], initials=i[2], bio=i[3], color_start=i[4], color_end=i[5])
            for i in IDOLS
        ]
    )
    db.flush()
    for group_id, idol_ids in MEMBERS.items():
        for idol_id in idol_ids:
            db.add(GroupMembership(group_id=group_id, idol_id=idol_id, start_date=date(2024, 1, 1)))
    db.add_all(
        [
            Card(
                id=i[0],
                title=i[1],
                idol_id=i[2],
                group_id=i[3],
                source=i[4],
                card_type=i[5],
                version=i[6],
                release_date=i[7],
                region=i[8],
                color_start=i[9],
                color_end=i[10],
            )
            for i in CARDS
        ]
    )
    db.flush()
    _seed_catalog_discovery(db)
    for priority, idol_id in enumerate(["idol-aria", "idol-lin", "idol-mina", "idol-yuna"]):
        db.add(UserIdol(user_id="current-user", idol_id=idol_id, priority=priority))
    db.add_all(
        [
            UserIdol(user_id="user-luna", idol_id="idol-lin", priority=0),
            UserIdol(user_id="user-luna", idol_id="idol-aria", priority=1),
            UserIdol(user_id="user-mint", idol_id="idol-yuna", priority=0),
            UserIdol(user_id="user-mint", idol_id="idol-mina", priority=1),
        ]
    )
    db.add(UserCollectionItem(user_id="current-user", card_id="card-aria-01", quantity=1))
    db.add(UserWishlistItem(user_id="current-user", card_id="card-lin-01"))
    for card_id in ["card-lin-01", "card-aria-01", "card-aria-02"]:
        db.add(UserCollectionItem(user_id="user-luna", card_id=card_id, quantity=1))
    db.add(UserWishlistItem(user_id="user-luna", card_id="card-yuna-01"))
    for card_id in ["card-yuna-01", "card-mina-01"]:
        db.add(UserCollectionItem(user_id="user-mint", card_id=card_id, quantity=1))
    db.add_all(
        [
            UserFollow(follower_id="current-user", following_id="user-luna"),
            UserFollow(follower_id="user-luna", following_id="current-user"),
            UserFollow(follower_id="user-mint", following_id="current-user"),
        ]
    )
    db.add_all(
        [
            CardAlbum(id="album-starlit", user_id="current-user", name="Starlit 收藏册"),
            CardAlbum(
                id="album-live",
                user_id="current-user",
                name="现场回忆",
                color_start=0xFFF2A8BB,
                color_end=0xFF87415D,
            ),
        ]
    )
    db.add(NotificationSetting(user_id="current-user"))
    _seed_social_posts(db)
    migrate_taxonomy(db)
    db.commit()


def _seed_social_posts(db: Session) -> None:
    now = datetime.now(UTC)
    contents = [
        "今天的舞台彩排顺利结束。新的编排加入了很多有趣细节，期待很快和大家见面！",
        "把巡演途中看到的晚霞分享给你们。谢谢每一座城市的相遇。",
        "新专辑的幕后记录更新啦，照片里还藏着一个小彩蛋。",
        "签售活动圆满结束，收到了许多温暖的话。",
        "练习室的一小段日常。最近正在挑战新的风格。",
    ]
    platforms = ["weibo", "instagram", "x", "xiaohongshu", "douyin"]
    idol_ids = [i[0] for i in IDOLS]
    group_by_idol = {idol: group for group, idols in MEMBERS.items() for idol in idols}
    for index in range(34):
        idol_id = idol_ids[index % len(idol_ids)]
        platform = platforms[index % len(platforms)]
        media_count = [1, 2, 4, 0, 3][index % 5]
        post = SocialPost(
            id=f"feed-{index + 1}",
            platform=platform,
            original_post_id=f"{platform}-post-{1000 + index}",
            idol_id=idol_id,
            group_id=group_by_idol[idol_id],
            posted_at=now - timedelta(hours=index * 3 + 1),
            content=contents[index % len(contents)],
            media=[
                {"type": "image", "url": None, "color_start": 0xFFBBA9FF, "color_end": 0xFF5A58A4}
                for _ in range(media_count)
            ],
            original_url={
                "weibo": "https://weibo.com",
                "instagram": "https://instagram.com",
                "x": "https://x.com",
                "xiaohongshu": "https://xiaohongshu.com",
                "douyin": "https://douyin.com",
            }[platform],
            fetched_at=now - timedelta(minutes=8 + index),
            relation={
                "type": "album",
                "target_id": "group-lumina",
                "title": "Starlit",
                "route": "/group/group-lumina",
            }
            if index % 3 == 0
            else None,
            is_available=index != 23,
            base_like_count=68 + index * 7,
            base_comment_count=4 + index % 19,
            share_count=index % 8,
        )
        db.add(post)
    db.flush()
    db.add_all(
        [
            Comment(
                id="feed-1-comment-1",
                post_id="feed-1",
                user_id="user-luna",
                content="今天的状态也太好了，已经开始期待正式舞台！",
            ),
            Comment(
                id="feed-1-comment-2",
                post_id="feed-1",
                user_id="user-mint",
                content="造型和灯光的氛围感都很喜欢。",
            ),
        ]
    )
