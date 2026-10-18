import { fileURLToPath } from 'node:url';
import { createSql, type Sql } from './db.js';
import { DEFAULT_SETTINGS } from './domain/types.js';
import { migrate } from './migrate.js';
import { SEED_HUBS, SEED_PRODUCTS, SEED_PROMOS } from './seed-data.js';
import { AuthService } from './services/auth.js';

export interface SeedOptions {
  adminEmail?: string;
  adminPassword?: string;
  /** Also create one demo staff account per branch. */
  demoStaffPassword?: string;
  nowMs?: number;
  log?: (m: string) => void;
}

/**
 * Idempotent: only inserts what's missing, so it's safe on every boot.
 * Menu, branches and promos are only seeded into an *empty* database.
 */
export async function seed(sql: Sql, auth: AuthService, opts: SeedOptions = {}): Promise<void> {
  const log = opts.log ?? console.log;
  const now = opts.nowMs ?? Date.now();

  await sql`insert into settings (key, value) values ('business', ${sql.json(DEFAULT_SETTINGS as never)}) on conflict do nothing`;

  const [{ count }] = await sql<{ count: string }[]>`select count(*) from products`;
  if (Number(count) === 0) {
    await sql`insert into hubs ${sql(SEED_HUBS as never)} on conflict do nothing`;
    for (const { stock, ovenMinutes, ...p } of SEED_PRODUCTS) {
      await sql`insert into products ${sql({
        ...p,
        crumbNotes: p.crumbNotes ?? null,
        reheatingTip: p.reheatingTip ?? null,
        imageUrls: sql.json(p.imageUrls as never),
        allergens: sql.json(p.allergens as never),
        dietaryTags: sql.json(p.dietaryTags as never),
        nutrition: p.nutrition ? sql.json(p.nutrition as never) : null,
        isListed: true,
      } as never)}`;
      for (const [i, hub] of SEED_HUBS.entries()) {
        await sql`insert into product_stock ${sql({
          productId: p.id,
          hubId: hub.id,
          remainingBatchStock: stock,
          currentBatchNumber: ovenMinutes == null ? 1 : 3,
          // Stagger the oven timers a little between branches.
          nextBatchReadyAt: ovenMinutes == null ? null : new Date(now + (ovenMinutes + i * 7) * 60_000),
        } as never)}`;
      }
    }
    for (const promo of SEED_PROMOS) await sql`insert into promo_codes ${sql(promo as never)} on conflict do nothing`;
    log(`seeded ${SEED_HUBS.length} branches, ${SEED_PRODUCTS.length} products, ${SEED_PROMOS.length} promo codes`);
  }

  if (opts.adminEmail && opts.adminPassword) {
    const email = opts.adminEmail.trim().toLowerCase();
    const [existing] = await sql`select 1 from users where email = ${email}`;
    if (!existing) {
      await sql`insert into users ${sql({ email, passwordHash: await auth.hashPassword(opts.adminPassword), name: 'Owner', role: 'admin' } as never)}`;
      log(`created admin ${email}`);
    }
  }

  if (opts.demoStaffPassword) {
    for (const hub of SEED_HUBS) {
      const email = `staff.${hub.id.replace('hub-', '')}@crumbandcraft.pk`;
      const [existing] = await sql`select 1 from users where email = ${email}`;
      if (existing) continue;
      await sql`insert into users ${sql({
        email,
        passwordHash: await auth.hashPassword(opts.demoStaffPassword),
        name: `${hub.name} Team`,
        role: 'staff',
        hubId: hub.id,
      } as never)}`;
      log(`created staff ${email}`);
    }
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const url = process.env.DATABASE_URL;
  const secret = process.env.JWT_SECRET ?? 'x'.repeat(32);
  if (!url) throw new Error('Set DATABASE_URL');
  const sql = createSql(url, 1);
  migrate(sql)
    .then(() =>
      seed(sql, new AuthService(secret), {
        adminEmail: process.env.ADMIN_EMAIL,
        adminPassword: process.env.ADMIN_PASSWORD,
        demoStaffPassword: process.env.DEMO_STAFF_PASSWORD,
      }),
    )
    .then(() => console.log('seed complete'))
    .finally(() => sql.end());
}
