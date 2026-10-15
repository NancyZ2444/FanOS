import { describe, expect, it } from "vitest";
import { validateCard } from "../src/pages/cardValidation";
import { emptyCard } from "../src/api/types";

const complete = () => ({
  ...emptyCard(),
  title: "Aria Starlit",
  group_id: "group-lumina",
  idol_id: "idol-aria",
  source_entity_id: "album-starlit",
  image_url: "https://example.test/front.webp",
  front_source: {
    source_type: "OFFICIAL",
    source_url: "https://example.test/source",
    copyright_status: "AUTHORIZED",
  },
});
describe("catalog publication requirements", () => {
  it("user-submitted image links are optional but copyright checks remain required", () => {
    const card = {
      ...complete(),
      front_source: {
        source_type: "USER_SUBMITTED",
        source_url: "",
        copyright_status: "AUTHORIZED",
      },
    };
    expect(validateCard(card, true)).toEqual([]);
    expect(
      validateCard(
        {
          ...card,
          front_source: { ...card.front_source, copyright_status: "UNKNOWN" },
        },
        true,
      ).map((e) => e.field),
    ).toEqual(["front_source.copyright_status"]);
    expect(
      validateCard(
        {
          ...card,
          front_source: { ...card.front_source, source_type: "OFFICIAL" },
        },
        true,
      ).map((e) => e.field),
    ).toContain("front_source.source_url");
  });
  it("does not require a hand-entered name or serial number", () => {
    expect(
      validateCard({ ...complete(), title: "", card_number: "" }, true),
    ).toEqual([]);
  });
  it("allows a minimal draft without pretending it is publishable", () => {
    const card = { ...emptyCard(), title: "Draft", group_id: "group-lumina" };
    expect(validateCard(card)).toEqual([]);
    expect(validateCard(card, true).map((e) => e.field)).toEqual(
      expect.arrayContaining(["idol_id", "image_url", "source_entity_id"]),
    );
  });
  it("accepts a valid personal card and a group card without an idol", () => {
    expect(validateCard(complete(), true)).toEqual([]);
    expect(
      validateCard({ ...complete(), idol_id: null, is_group_pc: true }, true),
    ).toEqual([]);
  });
  it("requires the back and AR resources only when those features are enabled", () => {
    const result = validateCard(
      { ...complete(), is_double_sided: true, has_ar: true },
      true,
    );
    expect(result.map((e) => e.field)).toEqual(
      expect.arrayContaining(["back_image_url", "ar_resource"]),
    );
  });
  it("rejects unknown and restricted image rights independently for each side", () => {
    const card = {
      ...complete(),
      back_image_url: "https://example.test/back.webp",
      back_source: {
        source_type: "USER_SUBMITTED",
        source_url: "https://example.test/back-source",
        copyright_status: "RESTRICTED",
      },
    };
    expect(validateCard(card, true).map((e) => e.field)).toEqual([
      "back_source.copyright_status",
    ]);
  });
});
