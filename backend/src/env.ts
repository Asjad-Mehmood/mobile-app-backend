function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable ${name} (see .env.example)`);
  return value;
}

export interface Env {
  port: number;
  /** Neon pooled connection string — used for queries. */
  databaseUrl: string;
  /** Neon direct (non-pooled) connection string — needed for LISTEN/NOTIFY realtime. */
  databaseUrlDirect: string;
  jwtSecret: string;
}

export function loadEnv(): Env {
  const jwtSecret = required('JWT_SECRET');
  if (jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters');
  const databaseUrl = required('DATABASE_URL');
  return {
    port: Number(process.env.PORT ?? 8080),
    databaseUrl,
    databaseUrlDirect: process.env.DATABASE_URL_DIRECT || databaseUrl,
    jwtSecret,
  };
}
