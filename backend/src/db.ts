import postgres from 'postgres';

export type Sql = postgres.Sql<Record<string, unknown>>;
export type Tx = postgres.TransactionSql<Record<string, unknown>>;
export type Db = Sql | Tx;

/**
 * Postgres client. snake_case columns come back as camelCase fields.
 * Neon: use the *pooled* connection string here (sslmode=require is read from the URL).
 */
export function createSql(url: string, max = 10): Sql {
  return postgres(url, {
    max,
    transform: postgres.camel,
    onnotice: () => {},
    // Neon's pooler doesn't support prepared statements across sessions.
    prepare: false,
  }) as unknown as Sql;
}
