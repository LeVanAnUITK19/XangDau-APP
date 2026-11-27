import mongoose, { Schema } from "mongoose";

export const fuelCodes = [
  "E5_RON_92",
  "E10_RON_95_III",
  "E10_RON_95_V",
  "RON_95_III",
  "RON_95_V",
  "DIESEL_001S",
  "DIESEL_005S",
  "KEROSENE",
  "MAZUT_180CST_35S",
] as const;
export type FuelCode = (typeof fuelCodes)[number];
export const fuels = mongoose.model(
  "Fuel",
  new Schema(
    {
      code: { type: String, required: true, unique: true },
      name: { type: String, required: true },
      category: {
        type: String,
        enum: ["gasoline", "diesel", "kerosene", "fuel_oil", "other"],
        required: true,
      },
      unit: { type: String, enum: ["liter", "kg"], required: true },
      active: { type: Boolean, default: true },
    },
    { timestamps: true, collection: "fuels" },
  ),
);

const priceSchema = new Schema(
  {
    fuelCode: { type: String, required: true },
    region: { type: String, enum: ["REGION_1", "REGION_2"], required: true },
    price: { type: Number, min: 0, required: true },
    unit: { type: String, enum: ["liter", "kg"], required: true },
    source: { type: String, required: true },
    sourceUrl: String,
    adjustmentId: String,
    effectiveAt: Date,
    effectiveDate: String,
    effectiveTimePrecision: {
      type: String,
      enum: ["datetime", "date", "unknown"],
      required: true,
    },
    observedAt: { type: Date, required: true },
    verified: { type: Boolean, default: true },
    recordKey: { type: String, required: true, unique: true },
  },
  { timestamps: true, collection: "price_records" },
);
priceSchema.index({ fuelCode: 1, region: 1, source: 1, effectiveAt: -1 });
priceSchema.index({ fuelCode: 1, region: 1, source: 1, effectiveDate: -1 });
export const PriceRecord = mongoose.model("PriceRecord", priceSchema);

const latestSchema = new Schema(
  {
    fuelCode: { type: String, required: true },
    region: { type: String, enum: ["REGION_1", "REGION_2"], required: true },
    source: { type: String, required: true },
    unit: { type: String, enum: ["liter", "kg"], required: true },
    currentPrice: { type: Number, required: true },
    previousPrice: Number,
    priceChange: Number,
    percentageChange: Number,
    effectiveAt: Date,
    effectiveDate: String,
    effectiveTimePrecision: { type: String, required: true },
    adjustmentId: String,
    currentRecordId: Schema.Types.ObjectId,
    previousRecordId: Schema.Types.ObjectId,
    observedAt: Date,
  },
  { timestamps: true, collection: "latest_prices" },
);
latestSchema.index({ fuelCode: 1, region: 1, source: 1 }, { unique: true });
export const LatestPrice = mongoose.model("LatestPrice", latestSchema);

export const SyncState = mongoose.model(
  "SyncState",
  new Schema(
    {
      key: { type: String, unique: true },
      lockedUntil: Date,
      lastSuccessfulSyncAt: Date,
      lastError: String,
      historyImported: { type: Boolean, default: false },
    },
    { timestamps: true, collection: "sync_state" },
  ),
);

export const Device = mongoose.model(
  "Device",
  new Schema(
    {
      installationId: { type: String, required: true, unique: true },
      credentialHash: { type: String, required: true },
      fcmToken: { type: String, default: null },
      platform: { type: String, enum: ["android", "ios"], required: true },
      appVersion: { type: String, required: true },
      notificationsEnabled: { type: Boolean, default: false },
      selectedFuelCodes: { type: [String], default: [] },
      selectedRegion: {
        type: String,
        enum: ["REGION_1", "REGION_2"],
        default: "REGION_1",
      },
      changeDirection: {
        type: String,
        enum: ["increase", "decrease", "both"],
        default: "both",
      },
      lastSeenAt: Date,
      active: { type: Boolean, default: true },
    },
    { timestamps: true, collection: "devices" },
  ),
);

export const NotificationEvent = mongoose.model(
  "NotificationEvent",
  new Schema(
    {
      eventKey: { type: String, required: true, unique: true },
      priceRecordId: Schema.Types.ObjectId,
      fuelCode: { type: String, required: true },
      region: { type: String, required: true },
      source: { type: String, required: true },
      oldPrice: { type: Number, required: true },
      newPrice: { type: Number, required: true },
      priceChange: { type: Number, required: true },
      direction: {
        type: String,
        enum: ["increase", "decrease"],
        required: true,
      },
      effectiveAt: { type: Date, required: true },
      status: {
        type: String,
        enum: ["pending", "processing", "completed", "failed"],
        default: "pending",
      },
      attempts: { type: Number, default: 0 },
      nextAttemptAt: { type: Date, default: Date.now },
      lastError: String,
    },
    { timestamps: true, collection: "notification_events" },
  ),
);
