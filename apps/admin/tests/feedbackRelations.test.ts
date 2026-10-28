import { describe, expect, it } from "vitest";
import type { CatalogEntity } from "../src/api/types";
import type { FeedbackRecord } from "../src/pages/feedback/types";
import {
  feedbackVersionOptions,
  initialCardChanges,
  sourceMatchesCard,
  updateCardRelations,
} from "../src/pages/feedback/relations";

describe("feedback version record mapping", () => {
  const record = (
    id: string,
    status = "PUBLISHED",
    entity_id = "album-one",
  ) => ({
    id,
    entity_type: "albums",
    entity_id,
    status,
    data: { name: `Version ${id}`, code: "PHOTO" },
  });
  const records = [
    record("new"),
    record("draft", "DRAFT"),
    record("offline", "OFFLINE"),
    record("archived", "ARCHIVED"),
    record("unrelated", "PUBLISHED", "album-two"),
    { ...record("event"), entity_type: "events" },
  ];

  it("reads the real CatalogRecord data.name and excludes other sources and unavailable versions", () => {
    const versions = feedbackVersionOptions(records, "ALBUM", "album-one");
    expect(versions.map((version) => version.id)).toEqual(["new", "draft"]);
    expect(versions[0].name).toBe("Version new");
    expect(versions[0].code).toBe("PHOTO");
  });

  it.each(["offline", "archived"])(
    "retains only the historical selected %s version",
    (retainedId) => {
      expect(
        feedbackVersionOptions(records, "ALBUM", "album-one", retainedId).map(
          (version) => version.id,
        ),
      ).toEqual(["new", "draft", retainedId]);
      expect(
        feedbackVersionOptions(records, "ALBUM", "album-two", retainedId).map(
          (version) => version.id,
        ),
      ).toEqual(["unrelated"]);
    },
  );

  it("accepts flat names for compatibility without showing the storage ID", () => {
    const versions = feedbackVersionOptions(
      [
        {
          id: "cat-123",
          entity_type: "albums",
          entity_id: "album-one",
          name: "Closure Moon",
          status: "PUBLISHED",
        },
      ],
      "ALBUM",
      "album-one",
    );
    expect(versions[0].name).toBe("Closure Moon");
  });
});

const source = (values: Partial<CatalogEntity>) =>
  ({ status: "PUBLISHED", ...values }) as CatalogEntity;
const sources = [
  source({ id: "album-idle", group_id: "idle" }),
  source({ id: "album-ive", group_id: "ive" }),
  source({
    id: "album-joint",
    artists: [
      { id: "miyeon", type: "idols" },
      { id: "yuqi", type: "idols" },
    ],
  }),
  source({ id: "album-solo", artists: [{ id: "miyeon", type: "idols" }] }),
  source({ id: "event-joint", artists: [{ id: "idle", type: "groups" }] }),
];
const card = {
  group_id: "idle",
  idol_id: "miyeon",
  source_entity_type: "ALBUM",
  is_group_pc: false,
  source_entity_id: "album-solo",
  entity_version_id: "version-solo",
  version: "Photobook",
};

describe("missing card feedback relations", () => {
  it("offers a group's sources plus the artist's solo and joint releases only", () => {
    expect(
      sources
        .filter((entry) => sourceMatchesCard(entry, card))
        .map((entry) => entry.id),
    ).toEqual(["album-idle", "album-joint", "album-solo", "event-joint"]);
    expect(
      sourceMatchesCard(sources[1], {
        ...card,
        missing_source_name: "I’ve",
      }),
    ).toBe(false);
  });

  it("matches solo ownership through artist participation, not two empty group IDs", () => {
    const solo = { ...card, group_id: "" };
    expect(sourceMatchesCard(sources[3], solo)).toBe(true);
    expect(
      sourceMatchesCard(source({ id: "unrelated", group_id: "" }), solo),
    ).toBe(false);
    expect(
      sourceMatchesCard(sources[1], {
        ...solo,
        source_entity_type: "OTHER",
      }),
    ).toBe(true);
  });

  it("clears a solo source and its version after switching to a different artist", () => {
    const next = updateCardRelations(card, { idol_id: "sakura" }, sources);
    expect(next.source_entity_id).toBe("");
    expect(next.entity_version_id).toBeNull();
    expect(next.version).toBe("");
    expect(
      updateCardRelations(
        { ...card, source_entity_id: "album-joint" },
        { idol_id: "yuqi" },
        sources,
      ).entity_version_id,
    ).toBe("version-solo");
  });

  it("clears version when source or source type changes and retains group releases", () => {
    expect(
      updateCardRelations(card, { source_entity_id: "album-idle" }, sources)
        .entity_version_id,
    ).toBeNull();
    expect(
      updateCardRelations(card, { source_entity_type: "EVENT" }, sources)
        .source_entity_id,
    ).toBe("");
    expect(
      updateCardRelations(
        { ...card, source_entity_id: "album-idle" },
        { idol_id: "yuqi" },
        sources,
      ).source_entity_id,
    ).toBe("album-idle");
    expect(
      updateCardRelations(card, { is_group_pc: true, idol_id: null }, sources)
        .source_entity_id,
    ).toBe("");
  });
});

describe("feedback draft and resubmission prefill", () => {
  const feedback = {
    draft: {
      ...card,
      image_url: "/old.png",
      front_source: { copyright_status: "AUTHORIZED" },
    },
    submission: {
      missing: {
        ...card,
        source_entity_id: "album-joint",
        source_version_id: "new-version",
        source_version_name: "New version",
      },
      front: { image_url: "/new.png" },
    },
    review: {},
  } as unknown as FeedbackRecord;

  it("uses the saved internal draft normally", () => {
    const values = initialCardChanges(feedback);
    expect(values.source_entity_id).toBe("album-solo");
    expect(values.image_url).toBe("/old.png");
    expect(values.front_source.copyright_status).toBe("AUTHORIZED");
  });

  it("shows resubmitted information and resets picture authorization for re-review", () => {
    const values = initialCardChanges({
      ...feedback,
      review: { submission_changed: true },
    });
    expect(values.source_entity_id).toBe("album-joint");
    expect(values.entity_version_id).toBe("new-version");
    expect(values.image_url).toBe("/new.png");
    expect(values.front_source.copyright_status).toBe("UNKNOWN");
  });

  it("keeps resubmitted base fields while showing the reviewer-approved patch", () => {
    const values = initialCardChanges({
      ...feedback,
      review: {
        submission_changed: true,
        submitted_payload: { changes: { card_type: "REGULAR" } },
        approved_payload: { changes: { source_entity_id: "album-verified" } },
      },
    });
    expect(values.source_entity_id).toBe("album-verified");
    expect(values.image_url).toBe("/new.png");
    expect(values.card_type).toBe("REGULAR");
  });

  it("restores legacy failed-action edits without guessing a source from its name", () => {
    const values = initialCardChanges({
      ...feedback,
      draft: undefined,
      review: {
        retry_changes: { source_entity_id: "", missing_source_name: "I’ve" },
      },
    });
    expect(values.source_entity_id).toBe("");
    expect(values.missing_source_name).toBe("I’ve");
  });
});
