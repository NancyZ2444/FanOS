# API integration notes

The app follows the Phase 1 envelope contract:

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

`ApiClient` validates this envelope and exposes only `data` to repositories. Pages never import or call Dio.

Current remote repository endpoints reserved by the app:

| Capability | Endpoint |
| --- | --- |
| Login | `POST /auth/login` |
| Catalog bootstrap | `GET /catalog/bootstrap` |
| Catalog lists | `GET /catalog/groups|idols|albums|events|cards|merchandise` |
| Catalog details | `GET /catalog/{entity}/{id}` |
| Cross-entity search | `GET /catalog/search?q=` |
| Daily draw | `POST /daily-cards/draw` |
| Scan readiness | `GET /scan/status` |
| Multi-card scan | `POST /scan/recognize` |
| Unrecognized card feedback | `POST /scan/feedback` |
| Idol social feed | `GET /idol-feed` |
| Refresh synchronized feed | `POST /idol-feed/refresh` |
| Fan OS post like | `PUT /idol-feed/{post_id}/like` |
| Post comments | `GET/POST /idol-feed/{post_id}/comments` |
| Comment reply | `POST /idol-feed/{post_id}/comments/{comment_id}/replies` |
| Comment moderation | `DELETE /comments/{comment_id}`, `POST /comments/{comment_id}/report` |
| Comment like | `PUT /comments/{comment_id}/like` |
| Current user profile | `GET/PATCH /me/profile` |
| Public user profile | `GET /users/{user_id}` |
| Follow relationship | `PUT/DELETE /users/{user_id}/follow` |
| Following / followers | `GET /users/{user_id}/following`, `GET /users/{user_id}/followers` |
| Profile privacy | `PATCH /me/privacy` |
| Digital card albums | `GET/POST /me/card-albums` |
| Profile photos | `GET/POST /me/profile-photos` |

Before enabling `USE_MOCK_API=false`, align these payloads with the approved OpenAPI contract. The daily draw request must be idempotent and all selection rules remain server-side.

## Profile and relationship contract

`GET /users/{user_id}` should return only fields permitted by the owner's
privacy settings. Asset sections use `null` for a private count and omit the
corresponding list payload. The app expects profile basics, level/EXP, main and
additional favorite Idol IDs, public Weibo identity, following/follower counts,
and collection/likes/album/photo summaries.

Following is idempotent: `PUT /users/{user_id}/follow` creates the relationship
and `DELETE` removes it. Both responses should include `relation_status`
(`none`, `follows_you`, `following`, or `mutual`) plus the updated follower
count. Collection and likes remain independent, user-scoped records. A card may
be Owned and Wishlist at the same time; changing Owned quantity never removes
Wishlist automatically.

After real API login, the app hydrates profile, favorite Idols, Owned quantities,
Wishlist, card albums, photos, and relation counts from `/me/profile`,
`/me/card-albums`, and `/me/profile-photos`. Production uploads return durable
asset URLs; iOS local picker paths are never saved as profile data.

## Multi-card scan contract

`GET /scan/status` exposes whether the official-card index is populated and
which extractor modes are active. The client may use it to distinguish a
temporarily unreachable API from an AI service that still needs card assets or
production models.

`POST /scan/recognize` uses `multipart/form-data` with an `image` file. Its
response `data` must use one session for both single-card and multi-card scans:

```json
{
  "session_id": "scan_01",
  "original_image_path": null,
  "detected_cards": [
    {
      "detected_card_id": "detected_01",
      "crop_image_path": null,
      "crop_region": {"x": 0.08, "y": 0.08, "width": 0.38, "height": 0.39},
      "recognition_status": "recommended",
      "user_confirmed_card_id": null,
      "candidates": [
        {
          "similarity": 0.96,
          "card": {"id": "card_01", "title": "..."}
        }
      ]
    }
  ]
}
```

Supported `recognition_status` values are `recommended`,
`needs_confirmation`, and `unrecognized`. Each detected card is independent;
an empty candidate list must not fail the full session.

`POST /scan/feedback` uses `multipart/form-data` with optional
`original_image` and a JSON `metadata` field. Metadata includes the scan
session ID, detected card ID, crop region, AI candidates and similarities,
user ID, optional group/Idol/source, and notes.

## Idol social feed contract

`GET /idol-feed` accepts optional `idol_ids`, `group_ids`, `author_type`,
`platform`, `cursor`, and `limit` (the app defaults to 20). The response keeps each third-party platform
independent so one failed source does not fail the complete feed:

```json
{
  "items": [
    {
      "id": "feed_01",
      "platform": "weibo",
      "original_post_id": "third_party_01",
      "social_account_id": "social_account_01",
      "author_type": "idol",
      "idol_id": "idol_01",
      "idol_name": "Aria",
      "group_id": "group-lumina",
      "group_name": "LUMINA",
      "post_time": "2026-09-15T08:00:00Z",
      "content": "...",
      "media": [{"type": "image", "url": "https://..."}],
      "original_url": "https://...",
      "deep_link_url": "sinaweibo://...",
      "fetch_time": "2026-09-15T08:05:00Z",
      "is_available": true,
      "like_count": 128,
      "comment_count": 32,
      "share_count": 0,
      "relation": {
        "type": "album",
        "target_id": "album_01",
        "title": "Starlit",
        "route": "/group/group-lumina"
      }
    }
  ],
  "next_cursor": "20",
  "new_count": 5,
  "unavailable_platforms": ["x"],
  "is_from_cache": false
}
```

Supported platforms are `weibo`, `instagram`, `x`, `xiaohongshu`, and
`douyin`. Pull-to-refresh reads the Fan OS synchronized dataset through
`POST /idol-feed/refresh`; it must not trigger direct synchronous fan-out to
all third-party platforms. Deleted source posts return `is_available: false`
without retaining public body content.

Global Feed, Group Detail, Member Detail, and post detail must resolve the
same `post_id`. Viewed, liked, and comment state is user-scoped and shared
across every entry point. Group Detail uses `group_ids`; Member Detail uses a
single `idol_id`. Both entity feeds remain strictly sorted by `post_time`.

Likes and comments are Fan OS interactions rather than writes to the source
platform. Comment replies accept one root `parent_id`; the service should
flatten deeper replies to a maximum of two visible levels. Deleting is allowed
only for the author, while reporting is allowed for other users' comments.
