import crypto from "node:crypto";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import pinoHttp from "pino-http";
import pino from "pino";
import mongoose from "mongoose";
import { config } from "./config";
import { Device, fuels, LatestPrice, PriceRecord, SyncState } from "./models";

export const logger = pino({ level: config.LOG_LEVEL });
export const app = express();
app.disable("x-powered-by");
app.use(helmet());
app.use(
  cors({
    origin: config.CORS_ORIGINS === "*" ? true : config.CORS_ORIGINS.split(","),
  }),
);
app.use(express.json({ limit: "32kb" }));
app.use(pinoHttp({ logger }));
app.use(
  rateLimit({
    windowMs: config.RATE_LIMIT_WINDOW_MS,
    limit: config.RATE_LIMIT_MAX_REQUESTS,
    standardHeaders: true,
    legacyHeaders: false,
  }),
);

const ok = (
  res: express.Response,
  data: unknown,
  meta: Record<string, unknown> = {},
) => res.json({ success: true, data, meta });
const regionSchema = (v: unknown) =>
  v === "REGION_2" ? "REGION_2" : "REGION_1";
const auth = (
  req: express.Request,
  res: express.Response,
  next: express.NextFunction,
) => {
  const provided =
    req.header("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const expected = config.SYNC_SECRET ?? "";
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (!expected || a.length !== b.length || !crypto.timingSafeEqual(a, b))
    return res.status(401).json({
      success: false,
      error: { code: "UNAUTHORIZED", message: "Không được phép" },
    });
  next();
};
const requireDb = (
  _req: express.Request,
  res: express.Response,
  next: express.NextFunction,
) => {
  if (mongoose.connection.readyState !== 1)
    return res.status(503).json({
      success: false,
      error: {
        code: "DATABASE_UNAVAILABLE",
        message: "Dữ liệu tạm thời chưa sẵn sàng",
      },
    });
  next();
};

app.get("/health", (_req, res) => res.json({ status: "ok" }));
app.get("/ready", (_req, res) =>
  mongoose.connection.readyState === 1
    ? res.json({ status: "ready" })
    : res.status(503).json({ status: "not_ready" }),
);
app.get("/openapi.json", (_req, res) =>
  res.json({
    openapi: "3.1.0",
    info: { title: "Giá Xăng Dầu API", version: "1.0.0" },
    servers: [{ url: "/" }],
    paths: {
      "/health": { get: { summary: "Liveness check" } },
      "/ready": { get: { summary: "Database readiness check" } },
      "/api/v1/fuels": { get: { summary: "List active fuels" } },
      "/api/v1/prices/latest": { get: { summary: "Latest prices by region" } },
      "/api/v1/prices/compare-regions": {
        get: { summary: "Compare regional prices" },
      },
      "/api/v1/prices/{fuelCode}": {
        get: { summary: "Fuel detail and recent history" },
      },
      "/api/v1/history": {
        get: { summary: "Price history and coverage metadata" },
      },
      "/api/v1/analytics/summary": { get: { summary: "Price period summary" } },
      "/api/v1/analytics/compare": {
        get: { summary: "Compare prices with matching units" },
      },
      "/api/v1/metadata": {
        get: { summary: "Data source and synchronization metadata" },
      },
      "/api/v1/internal/sync": {
        post: {
          summary: "Run protected upstream synchronization",
          security: [{ bearerAuth: [] }],
        },
      },
    },
    components: {
      securitySchemes: { bearerAuth: { type: "http", scheme: "bearer" } },
    },
  }),
);
app.get("/docs", (_req, res) =>
  res
    .type("html")
    .send(
      '<!doctype html><html><head><title>Giá Xăng Dầu API</title></head><body><h1>API documentation</h1><p>OpenAPI definition: <a href="/openapi.json">/openapi.json</a></p></body></html>',
    ),
);
app.get("/api/v1/fuels", requireDb, async (_req, res, next) => {
  try {
    ok(res, await fuels.find({ active: true }).select("-__v").lean());
  } catch (e) {
    next(e);
  }
});
app.get(
  "/api/v1/prices/compare-regions",
  requireDb,
  async (_req, res, next) => {
    try {
      const rows = await LatestPrice.find().lean();
      const byFuel = new Map<string, typeof rows>();
      for (const row of rows)
        byFuel.set(row.fuelCode, [...(byFuel.get(row.fuelCode) ?? []), row]);
      ok(
        res,
        [...byFuel.values()].map((group) => ({
          fuelCode: group[0]?.fuelCode,
          unit: group[0]?.unit,
          region1:
            group.find((x) => x.region === "REGION_1")?.currentPrice ?? null,
          region2:
            group.find((x) => x.region === "REGION_2")?.currentPrice ?? null,
        })),
      );
    } catch (e) {
      next(e);
    }
  },
);
app.get("/api/v1/prices/latest", requireDb, async (req, res, next) => {
  try {
    const rows = await LatestPrice.find({
      region: regionSchema(req.query.region),
    })
      .sort({ fuelCode: 1 })
      .lean();
    const sync = await SyncState.findOne({ key: "prices" }).lean();
    ok(res, rows, {
      source: rows[0]?.source ?? null,
      lastSuccessfulSyncAt: sync?.lastSuccessfulSyncAt ?? null,
      stale:
        !sync?.lastSuccessfulSyncAt ||
        Date.now() - sync.lastSuccessfulSyncAt.getTime() > 6 * 3600_000,
    });
  } catch (e) {
    next(e);
  }
});
app.get("/api/v1/prices/:fuelCode", requireDb, async (req, res, next) => {
  try {
    const region = regionSchema(req.query.region);
    const current = await LatestPrice.findOne({
      fuelCode: String(req.params.fuelCode).toUpperCase(),
      region,
    }).lean();
    if (!current)
      return res.status(404).json({
        success: false,
        error: {
          code: "NOT_FOUND",
          message: "Chưa có dữ liệu giá cho nhiên liệu này",
        },
      });
    const history = await PriceRecord.find({
      fuelCode: current.fuelCode,
      region,
      source: current.source,
    })
      .sort({ effectiveAt: -1, effectiveDate: -1 })
      .limit(100)
      .lean();
    ok(res, { current, history });
  } catch (e) {
    next(e);
  }
});
app.get("/api/v1/history", requireDb, async (req, res, next) => {
  try {
    const fuelCode = String(req.query.fuelCode ?? "").toUpperCase();
    const region = regionSchema(req.query.region);
    const days =
      ({ "7d": 7, "30d": 30, "1y": 365, "3y": 1095 } as Record<string, number>)[
        String(req.query.period ?? "30d")
      ] ?? 30;
    const from = new Date(Date.now() - days * 86400_000);
    const carry = await PriceRecord.findOne({
      fuelCode,
      region,
      $or: [
        { effectiveAt: { $lt: from } },
        {
          effectiveAt: null,
          effectiveDate: { $lt: from.toISOString().slice(0, 10) },
        },
      ],
    })
      .sort({ effectiveAt: -1, effectiveDate: -1 })
      .lean();
    const rows = await PriceRecord.find({
      fuelCode,
      region,
      $or: [
        { effectiveAt: { $gte: from } },
        {
          effectiveAt: null,
          effectiveDate: { $gte: from.toISOString().slice(0, 10) },
        },
      ],
    })
      .sort({ effectiveAt: 1, effectiveDate: 1 })
      .lean();
    const series = [...(carry ? [carry] : []), ...rows];
    const dates = series.flatMap((r) =>
      r.effectiveAt
        ? [r.effectiveAt]
        : r.effectiveDate
          ? [new Date(`${r.effectiveDate}T00:00:00Z`)]
          : [],
    );
    const sync = await SyncState.findOne({ key: "prices" }).lean();
    ok(
      res,
      {
        items: series,
        earliestAvailableDate: dates[0] ?? null,
        latestAvailableDate: dates.at(-1) ?? null,
        coverageStart: dates[0] ?? null,
        coverageEnd: dates.at(-1) ?? null,
        coverageComplete: false,
        knownDataGaps: [],
        historyImported: sync?.historyImported ?? false,
        availablePeriods: [],
      },
      { lastSuccessfulSyncAt: sync?.lastSuccessfulSyncAt ?? null },
    );
  } catch (e) {
    next(e);
  }
});
app.get("/api/v1/analytics/summary", requireDb, async (req, res, next) => {
  try {
    const fuelCode = String(req.query.fuelCode ?? "").toUpperCase();
    const region = regionSchema(req.query.region);
    const days =
      ({ "7d": 7, "30d": 30, "1y": 365, "3y": 1095 } as Record<string, number>)[
        String(req.query.period ?? "30d")
      ] ?? 30;
    const from = new Date(Date.now() - days * 86400_000);
    const rows = await PriceRecord.find({
      fuelCode,
      region,
      $or: [
        { effectiveAt: { $gte: from } },
        { effectiveDate: { $gte: from.toISOString().slice(0, 10) } },
      ],
    })
      .sort({ effectiveAt: 1 })
      .lean();
    const prices = rows.map((x) => x.price);
    ok(res, {
      fuelCode,
      region,
      currentPrice: prices.at(-1) ?? null,
      minPrice: prices.length ? Math.min(...prices) : null,
      maxPrice: prices.length ? Math.max(...prices) : null,
      changes: rows.length,
      coverageComplete: false,
      range: { from, to: new Date() },
    });
  } catch (e) {
    next(e);
  }
});
app.get("/api/v1/analytics/compare", requireDb, async (req, res, next) => {
  try {
    const unit = req.query.unit === "kg" ? "kg" : "liter";
    ok(
      res,
      await LatestPrice.find({ region: regionSchema(req.query.region), unit })
        .sort({ currentPrice: 1 })
        .lean(),
    );
  } catch (e) {
    next(e);
  }
});
app.get("/api/v1/metadata", requireDb, async (_req, res, next) => {
  try {
    ok(res, {
      source: "VietFuelAPI",
      sourceUrl: config.UPSTREAM_BASE_URL ?? null,
      lastSuccessfulSyncAt:
        (await SyncState.findOne({ key: "prices" }).lean())
          ?.lastSuccessfulSyncAt ?? null,
      historyImported:
        (await SyncState.findOne({ key: "prices" }).lean())?.historyImported ??
        false,
    });
  } catch (e) {
    next(e);
  }
});
app.post("/api/v1/internal/sync", auth, async (_req, res, next) => {
  try {
    const { syncPrices } = await import("./sync");
    ok(res, await syncPrices());
  } catch (e) {
    next(e);
  }
});
app.post("/api/v1/internal/history/import", auth, (_req, res) =>
  res.status(501).json({
    success: false,
    error: {
      code: "HISTORY_UNAVAILABLE",
      message: "Nguồn chưa cung cấp dữ liệu lịch sử đã xác minh",
    },
  }),
);
app.post(
  "/api/v1/internal/notifications/retry",
  auth,
  async (_req, res, next) => {
    try {
      const { dispatchPending } = await import("./notifications");
      ok(res, await dispatchPending(100));
    } catch (error) {
      next(error);
    }
  },
);

const deviceCredentials = (
  req: express.Request,
  res: express.Response,
  next: express.NextFunction,
) => {
  void (async () => {
    const id = String(req.params.installationId ?? "");
    const provided = req.header("x-installation-credential") ?? "";
    const device = await Device.findOne({ installationId: id, active: true });
    const expected = device?.credentialHash ?? "";
    const actual = crypto.createHash("sha256").update(provided).digest("hex");
    const a = Buffer.from(actual);
    const b = Buffer.from(expected || "0".repeat(64));
    if (
      !device ||
      !provided ||
      a.length !== b.length ||
      !crypto.timingSafeEqual(a, b)
    ) {
      res.status(401).json({
        success: false,
        error: {
          code: "DEVICE_UNAUTHORIZED",
          message: "Thiết bị chưa được xác thực",
        },
      });
      return;
    }
    res.locals.device = device;
    next();
  })().catch(next);
};
const validDevice = (body: unknown) => {
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;
  const b = body as Record<string, unknown>;
  return (
    typeof b.installationId === "string" &&
    /^[a-zA-Z0-9_-]{16,128}$/.test(b.installationId) &&
    ["android", "ios"].includes(String(b.platform)) &&
    typeof b.appVersion === "string" &&
    b.appVersion.length <= 32
  );
};
app.post("/api/v1/devices/register", requireDb, async (req, res, next) => {
  try {
    if (!validDevice(req.body))
      return res.status(400).json({
        success: false,
        error: {
          code: "VALIDATION_ERROR",
          message: "Thông tin thiết bị không hợp lệ",
        },
      });
    const credential = crypto.randomBytes(32).toString("base64url");
    const b = req.body as {
      installationId: string;
      platform: "android" | "ios";
      appVersion: string;
    };
    await Device.findOneAndUpdate(
      { installationId: b.installationId },
      {
        $set: {
          credentialHash: crypto
            .createHash("sha256")
            .update(credential)
            .digest("hex"),
          platform: b.platform,
          appVersion: b.appVersion,
          active: true,
          lastSeenAt: new Date(),
        },
        $setOnInsert: { notificationsEnabled: false },
      },
      { upsert: true, new: true },
    );
    res.status(201).json({
      success: true,
      data: { installationId: b.installationId, credential },
    });
  } catch (e) {
    next(e);
  }
});
app.get(
  "/api/v1/devices/:installationId/preferences",
  requireDb,
  deviceCredentials,
  (_req, res) => {
    const d = res.locals.device as InstanceType<typeof Device>;
    ok(res, {
      notificationsEnabled: d.notificationsEnabled,
      selectedFuelCodes: d.selectedFuelCodes,
      selectedRegion: d.selectedRegion,
      changeDirection: d.changeDirection,
    });
  },
);
app.put(
  "/api/v1/devices/:installationId/preferences",
  requireDb,
  deviceCredentials,
  async (req, res, next) => {
    try {
      const b = req.body as Record<string, unknown> | undefined;
      const allowed = [
        "notificationsEnabled",
        "selectedFuelCodes",
        "selectedRegion",
        "changeDirection",
      ];
      if (
        !b ||
        typeof b !== "object" ||
        Array.isArray(b) ||
        Object.keys(b).length === 0 ||
        Object.keys(b).some((k) => !allowed.includes(k)) ||
        (b.notificationsEnabled !== undefined &&
          typeof b.notificationsEnabled !== "boolean") ||
        (b.selectedFuelCodes !== undefined &&
          (!Array.isArray(b.selectedFuelCodes) ||
            b.selectedFuelCodes.some(
              (x) => typeof x !== "string" || !/^[A-Z0-9_]{2,40}$/.test(x),
            ))) ||
        (b.selectedRegion !== undefined &&
          !["REGION_1", "REGION_2"].includes(String(b.selectedRegion))) ||
        (b.changeDirection !== undefined &&
          !["increase", "decrease", "both"].includes(String(b.changeDirection)))
      )
        return res.status(400).json({
          success: false,
          error: {
            code: "VALIDATION_ERROR",
            message: "Tùy chọn thông báo không hợp lệ",
          },
        });
      const d = res.locals.device as InstanceType<typeof Device>;
      const saved = await Device.findByIdAndUpdate(
        d._id,
        { $set: b },
        { new: true },
      )
        .select("-credentialHash -fcmToken")
        .lean();
      ok(res, saved);
    } catch (e) {
      next(e);
    }
  },
);
app.put(
  "/api/v1/devices/:installationId/token",
  requireDb,
  deviceCredentials,
  async (req, res, next) => {
    try {
      const token = (req.body as Record<string, unknown>).fcmToken;
      if (typeof token !== "string" || token.length < 20 || token.length > 4096)
        return res.status(400).json({
          success: false,
          error: { code: "VALIDATION_ERROR", message: "Token không hợp lệ" },
        });
      const d = res.locals.device as InstanceType<typeof Device>;
      await Device.updateOne(
        { _id: d._id },
        { $set: { fcmToken: token, lastSeenAt: new Date() } },
      );
      ok(res, { registered: true });
    } catch (e) {
      next(e);
    }
  },
);
app.delete(
  "/api/v1/devices/:installationId",
  requireDb,
  deviceCredentials,
  async (_req, res, next) => {
    try {
      const d = res.locals.device as InstanceType<typeof Device>;
      await Device.updateOne(
        { _id: d._id },
        {
          $set: { active: false, fcmToken: null, notificationsEnabled: false },
        },
      );
      res.status(204).end();
    } catch (e) {
      next(e);
    }
  },
);

app.use((_req, res) =>
  res.status(404).json({
    success: false,
    error: { code: "NOT_FOUND", message: "Không tìm thấy đường dẫn" },
  }),
);
app.use(
  (
    err: unknown,
    _req: express.Request,
    res: express.Response,
    _next: express.NextFunction,
  ) => {
    logger.error({ err }, "Request failed");
    res.status(500).json({
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Có lỗi xảy ra, vui lòng thử lại",
      },
    });
  },
);
