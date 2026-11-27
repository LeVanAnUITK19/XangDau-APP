import { describe, expect, it } from "vitest";
import { selectHistoryWindow } from "../src/history";

describe("price history window", () => {
  it("keeps the most recent carry-forward record and sorts real records by date", () => {
    const records = [
      { id: "new", effectiveDate: "2026-11-26" },
      { id: "old", effectiveDate: "2026-09-26" },
      { id: "carry", effectiveDate: "2026-10-20" },
      { id: "middle", effectiveDate: "2026-11-01" },
    ];

    const result = selectHistoryWindow(
      records,
      new Date("2026-10-28T00:00:00.000Z"),
    );

    expect(result.records.map((record) => record.id)).toEqual([
      "carry",
      "middle",
      "new",
    ]);
    expect(result.dates.map((date) => date.toISOString().slice(0, 10))).toEqual(
      ["2026-10-20", "2026-11-01", "2026-11-26"],
    );
  });

  it("uses the observation time only when no effective date is available", () => {
    const records = [
      { id: "observed", observedAt: "2026-11-27T16:56:28.656Z" },
      { id: "invalid", effectiveDate: "not-a-date" },
    ];

    const result = selectHistoryWindow(
      records,
      new Date("2026-11-01T00:00:00.000Z"),
    );

    expect(result.records.map((record) => record.id)).toEqual(["observed"]);
    expect(result.dates[0].toISOString()).toBe("2026-11-27T16:56:28.656Z");
  });
});
