import type { CatalogEntity } from "../../api/types";
import type { FeedbackRecord, Values } from "./types";

export function feedbackVersionOptions(
  records: Values[],
  sourceType: string,
  sourceId: string,
  retainedId?: string | null,
) {
  const kind = { ALBUM: "albums", EVENT: "events", OTHER: "others" }[
    sourceType
  ];
  return records
    .filter(
      (record) =>
        record.entity_type === kind &&
        record.entity_id === sourceId &&
        (!["OFFLINE", "ARCHIVED"].includes(record.status) ||
          record.id === retainedId),
    )
    .map((record) => ({
      ...record,
      id: String(record.id),
      // CatalogRecord keeps business fields inside data, while feedback object
      // search returns flat names. Normalize at the boundary for both shapes.
      name: record.data?.name || record.name || "未命名版本",
      code: record.data?.code || record.code || "",
    }));
}

// Keep source eligibility aligned with the existing card editor and API:
// ownership can come from a group or any artist on a joint release.
export function sourceMatchesCard(source: CatalogEntity, card: Values) {
  return (
    card.source_entity_type === "OTHER" ||
    (!!card.group_id && source.group_id === card.group_id) ||
    source.artists?.some(
      (artist: { id: string }) =>
        artist.id === card.group_id ||
        (!card.is_group_pc && artist.id === card.idol_id),
    ) === true
  );
}

export function updateCardRelations(
  current: Values,
  updates: Values,
  sources: CatalogEntity[],
) {
  const next = { ...current, ...updates };
  if (
    "source_entity_type" in updates &&
    updates.source_entity_type !== current.source_entity_type
  )
    next.source_entity_id = "";
  const source = sources.find((entry) => entry.id === next.source_entity_id);
  if (source && !sourceMatchesCard(source, next)) next.source_entity_id = "";
  if (
    next.source_entity_id !== current.source_entity_id ||
    next.source_entity_type !== current.source_entity_type
  ) {
    next.entity_version_id = null;
    next.source_version_id = null;
    next.version = "";
    next.source_version_name = "";
  }
  return next;
}

export function initialCardChanges(item: FeedbackRecord): Values {
  const submission: Values = {
    ...item.submission.missing,
    entity_version_id: item.submission.missing?.source_version_id,
    version: item.submission.missing?.source_version_name || "",
    image_url: item.submission.front?.image_url,
    back_image_url: item.submission.back?.image_url,
    front_source: {
      source_type: "USER_SUBMITTED",
      copyright_status: "UNKNOWN",
    },
    back_source: {
      source_type: "USER_SUBMITTED",
      copyright_status: "UNKNOWN",
    },
  };
  const base = item.review?.submission_changed
    ? { ...item.draft, ...submission }
    : { ...submission, ...item.draft };
  return {
    ...base,
    ...item.review?.submitted_payload?.changes,
    ...item.review?.approved_payload?.changes,
    ...(!item.review?.submission_changed ? item.review?.retry_changes : {}),
  };
}
