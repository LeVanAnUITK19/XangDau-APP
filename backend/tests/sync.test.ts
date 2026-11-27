import { describe, expect, it } from "vitest";
import { normalizePayload } from "../src/sync";

describe("upstream normalization", () => {
  it("normalizes VietFuelAPI's documented region1/region2 price rows", () => {
    expect(
      normalizePayload({
        success: true,
        meta: { primarySource: "Petrolimex", priceDate: "2026-05-15" },
        data: [
          {
            name: "Xăng RON 95-III",
            region1: 24330,
            region2: 24810,
            unit: "VND/lít",
          },
          {
            name: "Xăng RON 95-V",
            region1: 24730,
            region2: 25220,
            unit: "VND/lít",
          },
        ],
      }),
    ).toMatchObject([
      {
        fuelCode: "RON_95_III",
        region: "REGION_1",
        price: 24330,
        effectiveDate: "2026-05-15",
      },
      {
        fuelCode: "RON_95_III",
        region: "REGION_2",
        price: 24810,
        effectiveDate: "2026-05-15",
      },
      {
        fuelCode: "RON_95_V",
        region: "REGION_1",
        price: 24730,
      },
      {
        fuelCode: "RON_95_V",
        region: "REGION_2",
        price: 25220,
      },
    ]);
  });

  it("normalizes explicit codes, regions and date-only effective periods", () => {
    expect(
      normalizePayload({
        data: [
          {
            code: "RON_95_III",
            name: "RON 95-III",
            region: "Vùng 1",
            price: 22980,
            effective_date: "2026-10-01",
          },
        ],
      }),
    ).toMatchObject([
      {
        fuelCode: "RON_95_III",
        region: "REGION_1",
        price: 22980,
        unit: "liter",
        effectiveDate: "2026-10-01",
      },
    ]);
  });
  it("maps known fuel names and keeps mazut in kilograms", () => {
    expect(
      normalizePayload([
        { name: "Dầu mazut 180CST 3.5S", region: "Vùng 2", price: 17480 },
      ])[0],
    ).toMatchObject({
      fuelCode: "MAZUT_180CST_35S",
      region: "REGION_2",
      unit: "kg",
    });
  });
  it("rejects unsupported and malformed payloads without inventing records", () => {
    expect(() => normalizePayload({ data: [] })).toThrow(
      "no valid fuel prices",
    );
    expect(() => normalizePayload({ result: "unknown" })).toThrow(
      "no recognized price array",
    );
  });
  it("ignores items without a valid region, code or positive price", () => {
    expect(() =>
      normalizePayload([{ code: "X", price: -1, region: "Vùng 1" }]),
    ).toThrow();
  });
});
