import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createSql, type Sql } from './db.js';

const MIGRATIONS_DIR = fileURLToPath(new URL('../migrations/', import.meta.url));

/** Applies every migrations/*.sql not yet recorded, in file-name order. Safe to run on every deploy. */
export async function migrate(sql: Sql, log: (m: string) => void = console.log): Promise<void> {
  await sql`create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())`;
  const applied = new Set((await sql<{ name: string }[]>`select name from schema_migrations`).map((r) => r.name));
  const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    if (applied.has(file)) continue;
    const text = await readFile(MIGRATIONS_DIR + file, 'utf8');
    await sql.begin(async (tx) => {
      await tx.unsafe(text);
      await tx`insert into schema_migrations (name) values (${file})`;
    });
    log(`applied ${file}`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const url = process.env.DATABASE_URL_DIRECT || process.env.DATABASE_URL;
  if (!url) throw new Error('Set DATABASE_URL');
  const sql = createSql(url, 1);
  migrate(sql)
    .then(() => console.log('migrations up to date'))
    .finally(() => sql.end());
}
