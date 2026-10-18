import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import WebSocket from 'ws';
import { startServer } from '../src/serve.js';
import { createTestContext, pickup, STAFF_PASSWORD, TODAY, type TestContext, waitFor } from './helpers.js';

let t: TestContext;
let server: ReturnType<typeof startServer>;
const PORT = 18000 + Math.floor(Math.random() * 1000);
const sockets: WebSocket[] = [];

function connect(token?: string) {
  const messages: any[] = [];
  const ws = new WebSocket(`ws://127.0.0.1:${PORT}/ws${token ? `?token=${token}` : ''}`);
  ws.on('message', (data) => messages.push(JSON.parse(String(data))));
  sockets.push(ws);
  return { ws, messages, ready: () => waitFor(() => messages.some((m) => m.type === 'hello')) };
}

beforeAll(async () => {
  t = await createTestContext();
  server = startServer(t.deps, PORT);
});
afterAll(async () => {
  sockets.forEach((s) => s.close());
  await server.close();
  await t.close();
});

describe('realtime sync over WebSockets + LISTEN/NOTIFY', () => {
  it('delivers each event only to the people who should see it', async () => {
    const alice = await t.register();
    const bob = await t.register();
    const f7 = await t.login('staff.f7@crumbandcraft.pk', STAFF_PASSWORD);
    const saddar = await t.login('staff.saddar@crumbandcraft.pk', STAFF_PASSWORD);

    const aliceWs = connect(alice.token);
    const bobWs = connect(bob.token);
    const f7Ws = connect(f7);
    const saddarWs = connect(saddar);
    const guestWs = connect();
    await Promise.all([aliceWs, bobWs, f7Ws, saddarWs, guestWs].map((c) => c.ready()));
    expect(f7Ws.messages[0]).toEqual({ type: 'hello', role: 'staff' });
    expect(guestWs.messages[0]).toEqual({ type: 'hello', role: 'guest' });

    // Alice orders at F-7 → Alice + F-7 staff hear it; Bob and Saddar staff don't. Stock change goes to everyone.
    const order = await t.call('POST', '/orders', pickup([{ productId: 'pastry-butter-croissant', quantity: 1 }], { date: TODAY, startMinute: 720 }), alice.token);
    expect(order.status).toBe(201);
    const created = (m: any) => m.type === 'order.created' && m.orderId === order.json.id;
    await waitFor(() => aliceWs.messages.some(created) && f7Ws.messages.some(created));
    await waitFor(() => guestWs.messages.some((m) => m.type === 'stock.updated' && m.productIds.includes('pastry-butter-croissant')));

    // Staff move it into the oven → Alice's tracker hears it live.
    await t.call('POST', `/staff/orders/${order.json.id}/status`, { status: 'IN_THE_OVEN' }, f7);
    await waitFor(() => aliceWs.messages.some((m) => m.type === 'order.updated' && m.status === 'IN_THE_OVEN'));

    await new Promise((r) => setTimeout(r, 200));
    expect(bobWs.messages.some((m) => m.type?.startsWith('order.'))).toBe(false);
    expect(saddarWs.messages.some((m) => m.type?.startsWith('order.'))).toBe(false);
    expect(guestWs.messages.some((m) => m.type?.startsWith('order.'))).toBe(false);
    expect(server.clientCount()).toBe(5);
  });
});
