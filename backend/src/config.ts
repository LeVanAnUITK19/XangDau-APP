import { z } from "zod";

const schema = z.object({
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),
  PORT: z.coerce.number().int().positive().default(3000),
  MONGODB_URI: z.string().optional(),
  MONGODB_DB_NAME: z.string().default("viet_fuel"),
  UPSTREAM_BASE_URL: z.string().url().optional(),
  UPSTREAM_SOURCE: z.string().default("petrolimex"),
  UPSTREAM_TIMEOUT_MS: z.coerce.number().int().positive().default(15000),
  SYNC_SECRET: z.string().optional(),
  SYNC_ENABLED: z.string().default("true"),
  SYNC_ON_STARTUP: z.string().default("false"),
  FIREBASE_ENABLED: z.string().default("false"),
  FIREBASE_PROJECT_ID: z.string().optional(),
  FIREBASE_SERVICE_ACCOUNT_JSON_BASE64: z.string().optional(),
  LOG_LEVEL: z.string().default("info"),
  CORS_ORIGINS: z.string().default("*"),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60000),
  RATE_LIMIT_MAX_REQUESTS: z.coerce.number().default(120),
  SWAGGER_ENABLED: z.string().default("true"),
});

export const config = schema.parse(process.env);
