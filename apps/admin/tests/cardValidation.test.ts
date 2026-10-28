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
  it("publishes without manual image provenance or copyright fields", () => {
    const card = {
      ...complete(),
      front_source: undefined,
      back_source: undefined,
    };
    expect(validateCard(card, true)).toEqual([]);
    expect(
      validateCard({ ...card, source_entity_id: "" }, true).map((e) => e.field),
    ).toContain("source_entity_id");
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
  it("does not overwrite historical provenance when validating publication", () => {
    const card = {
      ...complete(),
      front_source: {
        source_type: "USER_SUBMITTED",
        source_url: "",
        copyright_status: "UNKNOWN",
      },
    };
    expect(validateCard(card, true)).toEqual([]);
    expect(card.front_source.copyright_status).toBe("UNKNOWN");
  });
});
