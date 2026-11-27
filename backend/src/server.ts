import "dotenv/config";
import { app, logger } from "./app";
import { config } from "./config";
import { connectDatabase, disconnectDatabase } from "./database";

async function start() {
  await connectDatabase();
  const server = app.listen(config.PORT, "0.0.0.0", () =>
    logger.info({ port: config.PORT }, "Fuel API listening"),
  );
  const stop = () => {
    server.close(() => {
      void disconnectDatabase().finally(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}
start().catch((error) => {
  logger.fatal({ error }, "Unable to start server");
  process.exit(1);
});
