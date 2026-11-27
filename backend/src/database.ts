import mongoose from "mongoose";
import { config } from "./config";

export async function connectDatabase(): Promise<void> {
  if (!config.MONGODB_URI)
    throw new Error("MONGODB_URI is required to start the API");
  mongoose.set("sanitizeFilter", true);
  await mongoose.connect(config.MONGODB_URI, {
    dbName: config.MONGODB_DB_NAME,
    maxPoolSize: 5,
    serverSelectionTimeoutMS: 10000,
  });
}

export async function disconnectDatabase(): Promise<void> {
  await mongoose.disconnect();
}
