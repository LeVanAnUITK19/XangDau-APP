import "dotenv/config";
import { connectDatabase, disconnectDatabase } from "../database";
import { syncPrices } from "../sync";
async function main() {
  try {
    await connectDatabase();
    process.stdout.write(`${JSON.stringify(await syncPrices())}\n`);
  } finally {
    await disconnectDatabase();
  }
}
main().catch((e) => {
  process.stderr.write(`${e instanceof Error ? e.message : "Sync failed"}\n`);
  process.exit(1);
});
