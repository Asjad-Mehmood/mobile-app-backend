import { createSql } from './db.js';
import { loadEnv } from './env.js';
import { migrate } from './migrate.js';
import { seed } from './seed.js';
import { startServer } from './serve.js';
import { AuthService } from './services/auth.js';
import { EventBus } from './services/events.js';

/** Production entry: migrate, seed what's missing, start HTTP + WebSocket server. */
async function main() {
  const env = loadEnv();
  const sql = createSql(env.databaseUrl);
  const auth = new AuthService(env.jwtSecret);

  await migrate(sql);
  await seed(sql, auth, {
    adminEmail: process.env.ADMIN_EMAIL,
    adminPassword: process.env.ADMIN_PASSWORD,
    demoStaffPassword: process.env.DEMO_STAFF_PASSWORD,
  });

  const bus = new EventBus(sql, env.databaseUrlDirect);
  await bus.start();

  const server = startServer({ sql, bus, auth, now: Date.now }, env.port, { log: true });
  console.log(`Crumb & Craft API listening on :${env.port}`);

  const shutdown = async () => {
    await server.close();
    await bus.stop();
    await sql.end({ timeout: 5 });
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
