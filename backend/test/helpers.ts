import { randomUUID } from 'node:crypto';
import postgres from 'postgres';
import { createApp } from '../src/app.js';
import { createSql } from '../src/db.js';
import type { AppDeps } from '../src/http.js';
import { migrate } from '../src/migrate.js';
import { seed } from '../src/seed.js';
import { AuthService } from '../src/services/auth.js';
import { EventBus, type AppEvent } from '../src/services/events.js';

const ADMIN_URL = process.env.TEST_DATABASE_URL ?? 'postgres://postgres@127.0.0.1:55432/postgres';

/** Sunday 18 Oct 2026, 10:00 in Islamabad (UTC+5). */
export const TEST_NOW = Date.parse('2026-10-18T05:00:00Z');
export const TODAY = '2026-10-18';
export const TOMORROW = '2026-10-19';

export const ADMIN = { email: 'admin@test.pk', password: 'admin-pass-123' };
export const STAFF_PASSWORD = 'staff-pass-123';

export const KOHSAR = { lat: 33.7286, lng: 73.0726 }; // F-6, ~1.7 km from F-7 branch
export const MURREE = { lat: 33.907, lng: 73.3943 };

export interface TestContext {
  deps: AppDeps;
  url: string;
  clock: { now: () => number; set: (t: number) => void; advance: (ms: number) => void };
  events: AppEvent[];
  call: <T = any>(method: string, path: string, body?: unknown, token?: string) => Promise<{ status: number; json: T }>;
  login: (email: string, password: string) => Promise<string>;
  register: (email?: string) => Promise<{ token: string; userId: string }>;
  close: () => Promise<void>;
}

/** A brand-new migrated + seeded database per test file. */
export async function createTestContext(): Promise<TestContext> {
  const dbName = 'crumb_test_' + randomUUID().replace(/-/g, '').slice(0, 10);
  const admin = postgres(ADMIN_URL, { max: 1, onnotice: () => {} });
  await admin.unsafe(`create database ${dbName}`);
  await admin.end();
  const url = ADMIN_URL.replace(/\/[^/]*$/, `/${dbName}`);

  let now = TEST_NOW;
  const clock = { now: () => now, set: (t: number) => (now = t), advance: (ms: number) => (now += ms) };
  const sql = createSql(url, 5);
  const auth = new AuthService('test-secret-test-secret-test-secret-!!');
  await migrate(sql, () => {});
  await seed(sql, auth, { adminEmail: ADMIN.email, adminPassword: ADMIN.password, demoStaffPassword: STAFF_PASSWORD, nowMs: now, log: () => {} });
  const bus = new EventBus(sql, url);
  await bus.start();
  const events: AppEvent[] = [];
  bus.subscribe((e) => events.push(e));

  const deps: AppDeps = { sql, bus, auth, now: clock.now };
  const app = createApp(deps);

  const call: TestContext['call'] = async (method, path, body, token) => {
    const res = await app.request(path, {
      method,
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, json: await res.json() };
  };

  const login = async (email: string, password: string) => {
    const res = await call('POST', '/auth/login', { email, password });
    if (res.status !== 200) throw new Error(`login failed: ${JSON.stringify(res.json)}`);
    return res.json.token as string;
  };

  let counter = 0;
  const register = async (email = `customer${++counter}@test.pk`) => {
    const res = await call('POST', '/auth/register', { email, password: 'customer-pass', name: 'Test Customer', phone: '03001234567' });
    if (res.status !== 201) throw new Error(`register failed: ${JSON.stringify(res.json)}`);
    return { token: res.json.token as string, userId: res.json.user.id as string };
  };

  return {
    deps,
    url,
    clock,
    events,
    call,
    login,
    register,
    close: async () => {
      await bus.stop();
      await sql.end({ timeout: 1 });
      const a = postgres(ADMIN_URL, { max: 1, onnotice: () => {} });
      await a.unsafe(`drop database if exists ${dbName} with (force)`);
      await a.end();
    },
  };
}

export const cake = (overrides: Record<string, unknown> = {}) => ({
  sizeId: 'ONE_KG',
  spongeId: 'BELGIAN_DARK_CHOCOLATE',
  fillingId: 'HAZELNUT_PRALINE',
  frostingId: 'MASCARPONE_WHIPPED_CREAM',
  eggless: false,
  message: 'Happy Birthday Ammi',
  fontId: 'SCRIPT',
  ...overrides,
});

export const pickup = (items: unknown[], slot: { date: string; startMinute: number } | null, extra: Record<string, unknown> = {}) => ({
  hubId: 'hub-f7',
  fulfillmentType: 'PICKUP',
  slot,
  paymentMethod: 'CASH_ON_DELIVERY',
  items,
  ...extra,
});

export const waitFor = async (predicate: () => boolean, timeoutMs = 3000) => {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeoutMs) throw new Error('timed out waiting for condition');
    await new Promise((r) => setTimeout(r, 20));
  }
};
