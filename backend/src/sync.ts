import crypto from "node:crypto";
import mongoose from "mongoose";
import { config } from "./config";
import {
  fuels,
  LatestPrice,
  NotificationEvent,
  PriceRecord,
  SyncState,
} from "./models";

type NormalizedPrice = {
  fuelCode: string;
  name: string;
  region: "REGION_1" | "REGION_2";
  price: number;
  unit: "liter" | "kg";
  effectiveDate?: string;
  effectiveAt?: Date;
  adjustmentId?: string;
};
const names: Record<string, string> = {
  "xăng e5 ron 92": "E5_RON_92",
  "e5 ron 92": "E5_RON_92",
  "xăng e5 ron 92 mức 2": "E5_RON_92",
  "e5 ron 92 mức 2": "E5_RON_92",
  "xăng e10 ron 95 mức 3": "E10_RON_95_III",
  "e10 ron 95 mức 3": "E10_RON_95_III",
  "xăng e10 ron 95 mức 5": "E10_RON_95_V",
  "e10 ron 95 mức 5": "E10_RON_95_V",
  "xăng ron 95-iii": "RON_95_III",
  "ron 95-iii": "RON_95_III",
  "xăng ron 95-v": "RON_95_V",
  "ron 95-v": "RON_95_V",
  "dầu diesel 0.05s": "DIESEL_005S",
  "diesel 0.05s": "DIESEL_005S",
  "do 0,001s mức 5": "DIESEL_001S",
  "dầu hỏa 2-k": "KEROSENE",
  "do 0,05s mức 2": "DIESEL_005S",
  "dầu hỏa": "KEROSENE",
  "dầu mazut 180cst 3.5s": "MAZUT_180CST_35S",
};
export function normalizePayload(payload: unknown): NormalizedPrice[] {
  const root = payload as {
    data?: unknown;
    prices?: unknown;
    items?: unknown;
    meta?: { priceDate?: unknown; priceDateDisplay?: unknown };
  };
  const raw = Array.isArray(payload)
    ? payload
    : Array.isArray(root?.data)
      ? root.data
      : Array.isArray(root?.prices)
        ? root.prices
        : Array.isArray(root?.items)
          ? root.items
          : null;
  if (!raw) throw new Error("Upstream response has no recognized price array");
  const out: NormalizedPrice[] = [];
  for (const item of raw as Record<string, unknown>[]) {
    const rawName = String(
      item.fuelName ?? item.fuel_name ?? item.name ?? item.fuel ?? "",
    ).trim();
    const code = String(
      item.fuelCode ??
        item.fuel_code ??
        item.code ??
        names[rawName.toLowerCase()] ??
        "",
    ).toUpperCase();
    const unitText = String(item.unit ?? "").toLowerCase();
    const unit = /kg/.test(unitText) || /mazut/i.test(rawName) ? "kg" : "liter";
    const effective =
      item.effectiveAt ??
      item.effective_at ??
      item.effectiveDate ??
      item.effective_date ??
      root.meta?.priceDate;
    const date = typeof effective === "string" ? effective : undefined;
    const parsed = date ? new Date(date) : null;
    const effectiveFields =
      date && parsed && !Number.isNaN(parsed.getTime())
        ? date.length > 10
          ? { effectiveAt: parsed, effectiveDate: date.slice(0, 10) }
          : { effectiveDate: date.slice(0, 10) }
        : {};
    const adjustmentId =
      String(item.adjustmentId ?? item.adjustment_id ?? "") || undefined;

    // VietFuelAPI's documented aggregate response gives both region prices
    // on each fuel row rather than one row per region.
    if (item.region1 !== undefined || item.region2 !== undefined) {
      for (const [field, region] of [
        ["region1", "REGION_1"],
        ["region2", "REGION_2"],
      ] as const) {
        const price = Number(item[field]);
        if (code && Number.isFinite(price) && price > 0) {
          out.push({
            fuelCode: code,
            name: rawName || code,
            region,
            price,
            unit,
            ...effectiveFields,
            adjustmentId,
          });
        }
      }
      continue;
    }

    const price = Number(item.price ?? item.price_vnd ?? item.value);
    const rawRegion = String(
      item.region ?? item.area ?? item.zone ?? "",
    ).toLowerCase();
    const region = /(?:^|\D)2|ii|south|miền nam|vùng 2/.test(rawRegion)
      ? "REGION_2"
      : /(?:^|\D)1|i|north|vùng 1|toàn quốc/.test(rawRegion)
        ? "REGION_1"
        : null;
    if (code && Number.isFinite(price) && price > 0 && region) {
      out.push({
        fuelCode: code,
        name: rawName || code,
        region,
        price,
        unit,
        ...effectiveFields,
        adjustmentId,
      });
    }
  }
  if (!out.length) throw new Error("Upstream returned no valid fuel prices");
  return out;
}

export async function syncPrices(fetcher: typeof fetch = fetch): Promise<{
  updated: number;
  unchanged: number;
  observedAt: string;
  notificationDispatch?: {
    enabled: boolean;
    delivered: number;
    pending?: number;
    processed?: number;
  };
}> {
  if (config.SYNC_ENABLED !== "true") throw new Error("Price sync is disabled");
  if (!config.UPSTREAM_BASE_URL)
    throw new Error("UPSTREAM_BASE_URL is not configured");
  const lock = await SyncState.findOneAndUpdate(
    {
      key: "prices",
      $or: [
        { lockedUntil: mongoose.trusted({ $lt: new Date() }) },
        { lockedUntil: null },
      ],
    },
    { $set: { lockedUntil: new Date(Date.now() + 120_000) } },
    { upsert: true, new: true },
  );
  if (!lock) throw new Error("A price synchronization is already running");
  const observedAt = new Date();
  try {
    let response: Response;
    const endpoint = `${config.UPSTREAM_BASE_URL.replace(/\/$/, "")}/api/fuel-prices/${encodeURIComponent(config.UPSTREAM_SOURCE)}`;
    for (let attempt = 0; ; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(
        () => controller.abort(),
        config.UPSTREAM_TIMEOUT_MS,
      );
      try {
        response = await fetcher(endpoint, { signal: controller.signal });
      } catch (error) {
        if (attempt >= 2) throw error;
        await new Promise((resolve) =>
          setTimeout(resolve, 250 * 2 ** attempt + Math.random() * 250),
        );
        continue;
      } finally {
        clearTimeout(timer);
      }
      if (
        response.ok ||
        (response.status < 500 && response.status !== 429) ||
        attempt >= 2
      )
        break;
      const retryAfter = Number(response.headers.get("retry-after"));
      const delay =
        Number.isFinite(retryAfter) && retryAfter > 0
          ? Math.min(retryAfter * 1000, 5000)
          : 250 * 2 ** attempt + Math.random() * 250;
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
    if (!response.ok)
      throw new Error(`Upstream request failed (${response.status})`);
    const normalized = normalizePayload(await response.json());
    let updated = 0;
    let unchanged = 0;
    for (const item of normalized) {
      const recordKey = crypto
        .createHash("sha256")
        .update(
          [
            item.fuelCode,
            item.region,
            config.UPSTREAM_SOURCE,
            item.effectiveAt?.toISOString() ??
              item.effectiveDate ??
              observedAt.toISOString().slice(0, 10),
            item.price,
          ].join("|"),
        )
        .digest("hex");
      const prior = await LatestPrice.findOne({
        fuelCode: item.fuelCode,
        region: item.region,
        source: config.UPSTREAM_SOURCE,
      }).lean();
      const precision = item.effectiveAt
        ? "datetime"
        : item.effectiveDate
          ? "date"
          : "unknown";
      const category = item.fuelCode.startsWith("DIESEL")
        ? "diesel"
        : item.fuelCode === "KEROSENE"
          ? "kerosene"
          : item.fuelCode.startsWith("MAZUT")
            ? "fuel_oil"
            : item.fuelCode.includes("RON")
              ? "gasoline"
              : "other";
      await fuels.updateOne(
        { code: item.fuelCode },
        { $set: { name: item.name, category, unit: item.unit, active: true } },
        { upsert: true },
      );
      if (
        prior?.currentPrice === item.price &&
        prior.effectiveDate === item.effectiveDate
      ) {
        unchanged++;
        continue;
      }
      const record = await PriceRecord.findOneAndUpdate(
        { recordKey },
        {
          $setOnInsert: {
            ...item,
            source: config.UPSTREAM_SOURCE,
            sourceUrl: `${config.UPSTREAM_BASE_URL.replace(/\/$/, "")}/api/fuel-prices/${encodeURIComponent(config.UPSTREAM_SOURCE)}`,
            observedAt,
            verified: true,
            recordKey,
            effectiveTimePrecision: precision,
          },
        },
        { upsert: true, new: true },
      );
      const change = prior ? item.price - prior.currentPrice : null;
      if (item.effectiveAt && item.effectiveAt > observedAt) continue;
      if (
        !item.effectiveAt &&
        item.effectiveDate &&
        item.effectiveDate > observedAt.toISOString().slice(0, 10)
      )
        continue;
      await LatestPrice.findOneAndUpdate(
        {
          fuelCode: item.fuelCode,
          region: item.region,
          source: config.UPSTREAM_SOURCE,
        },
        {
          $set: {
            ...item,
            source: config.UPSTREAM_SOURCE,
            currentPrice: item.price,
            previousPrice: prior?.currentPrice,
            priceChange: change,
            percentageChange: prior?.currentPrice
              ? (change! / prior.currentPrice) * 100
              : null,
            currentRecordId: record._id,
            effectiveTimePrecision: precision,
            observedAt,
          },
        },
        { upsert: true, new: true },
      );
      if (
        prior &&
        change !== null &&
        change !== 0 &&
        item.effectiveAt &&
        item.effectiveAt <= observedAt
      ) {
        await NotificationEvent.updateOne(
          { eventKey: recordKey },
          {
            $setOnInsert: {
              eventKey: recordKey,
              priceRecordId: record._id,
              fuelCode: item.fuelCode,
              region: item.region,
              source: config.UPSTREAM_SOURCE,
              oldPrice: prior.currentPrice,
              newPrice: item.price,
              priceChange: change,
              direction: change > 0 ? "increase" : "decrease",
              effectiveAt: item.effectiveAt,
              status: "pending",
              attempts: 0,
              nextAttemptAt: observedAt,
            },
          },
          { upsert: true },
        );
      }
      updated++;
    }
    let notificationDispatch:
      | {
          enabled: boolean;
          delivered: number;
          pending?: number;
          processed?: number;
        }
      | undefined;
    try {
      const { dispatchPending } = await import("./notifications");
      notificationDispatch = await dispatchPending(50);
    } catch {
      // Price persistence succeeds independently; pending events can retry later.
    }
    await SyncState.updateOne(
      { key: "prices" },
      {
        $set: {
          lastSuccessfulSyncAt: observedAt,
          lastError: null,
          lockedUntil: new Date(0),
        },
      },
    );
    return {
      updated,
      unchanged,
      observedAt: observedAt.toISOString(),
      notificationDispatch,
    };
  } catch (e) {
    await SyncState.updateOne(
      { key: "prices" },
      {
        $set: {
          lastError: e instanceof Error ? e.message : "Sync failed",
          lockedUntil: new Date(0),
        },
      },
    );
    throw e;
  }
}
