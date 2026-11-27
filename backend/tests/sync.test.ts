import { describe, expect, it } from "vitest";
import mongoose from "mongoose";
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
  it("normalizes the current Petrolimex product names without merging fuel grades", () => {
    const rows = normalizePayload({
      meta: { priceDate: "2026-11-26" },
      data: [
        { name: "Dầu hỏa 2-K", region1: 1000, region2: 1100, unit: "VND/lít" },
        {
          name: "DO 0,001S Mức 5",
          region1: 1200,
          region2: 1300,
          unit: "VND/lít",
        },
        {
          name: "DO 0,05S Mức 2",
          region1: 1400,
          region2: 1500,
          unit: "VND/lít",
        },
        {
          name: "Xăng E10 RON 95 Mức 3",
          region1: 1600,
          region2: 1700,
          unit: "VND/lít",
        },
        {
          name: "Xăng E10 RON 95 Mức 5",
          region1: 1800,
          region2: 1900,
          unit: "VND/lít",
        },
        {
          name: "Xăng E5 RON 92 Mức 2",
          region1: 2000,
          region2: 2100,
          unit: "VND/lít",
        },
      ],
    });

    expect(
      rows
        .filter((row) => row.region === "REGION_1")
        .map((row) => row.fuelCode),
    ).toEqual([
      "KEROSENE",
      "DIESEL_001S",
      "DIESEL_005S",
      "E10_RON_95_III",
      "E10_RON_95_V",
      "E5_RON_92",
    ]);
    expect(rows).toHaveLength(12);
    expect(rows[7]).toMatchObject({
      fuelCode: "E10_RON_95_III",
      region: "REGION_2",
      effectiveDate: "2026-11-26",
    });
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

describe("sync lock filter", () => {
  it("preserves its internal date operator when Mongoose sanitizes filters", () => {
    const now = new Date("2026-11-27T12:00:00.000Z");
    const filter = {
      key: "prices",
      $or: [
        { lockedUntil: mongoose.trusted({ $lt: now }) },
        { lockedUntil: null },
      ],
    };

    const sanitized = mongoose.sanitizeFilter(filter);
    const lockUntil = (sanitized.$or as Array<{ lockedUntil: unknown }>)[0]
      ?.lockedUntil;

    expect(lockUntil).toMatchObject({ $lt: now });
    expect(lockUntil).not.toHaveProperty("$eq");
  });
});
