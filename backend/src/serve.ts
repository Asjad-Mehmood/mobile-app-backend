import { serve, type ServerType } from '@hono/node-server';
import { createNodeWebSocket } from '@hono/node-ws';
import type { WSContext } from 'hono/ws';
import { createApp } from './app.js';
import type { AppDeps } from './http.js';
import type { AuthUser } from './services/auth.js';
import type { AppEvent } from './services/events.js';
import { mapUser } from './services/repo.js';

interface Client {
  ws: WSContext;
  user: AuthUser | null;
}

/** Who should hear about an event. Menu/stock changes go to everyone; orders only to the people involved. */
export function shouldDeliver(event: AppEvent, user: AuthUser | null): boolean {
  if (event.type !== 'order.created' && event.type !== 'order.updated') return true;
  if (!user) return false;
  if (user.role === 'admin') return true;
  if (user.role === 'staff') return user.hubId == null || user.hubId === event.hubId;
  return user.id === event.userId;
}

/**
 * HTTP API + realtime WebSocket at /ws?token=<jwt>.
 * Clients receive small JSON events ({"type":"order.updated","orderId":...}) and re-fetch what changed.
 */
export function startServer(deps: AppDeps, port: number, opts: { log?: boolean } = {}) {
  const app = createApp(deps, opts);
  const { injectWebSocket, upgradeWebSocket } = createNodeWebSocket({ app });
  const clients = new Set<Client>();

  app.get(
    '/ws',
    upgradeWebSocket((c) => {
      const token = c.req.query('token');
      let client: Client | null = null;
      return {
        async onOpen(_event, ws) {
          let user: AuthUser | null = null;
          if (token) {
            const id = await deps.auth.verify(token);
            if (id) {
              const [row] = await deps.sql`select * from users where id = ${id} and is_active`;
              if (row) user = mapUser(row);
            }
          }
          client = { ws, user };
          clients.add(client);
          ws.send(JSON.stringify({ type: 'hello', role: user?.role ?? 'guest' }));
        },
        onMessage(event, ws) {
          if (event.data === 'ping') ws.send(JSON.stringify({ type: 'pong' }));
        },
        onClose() {
          if (client) clients.delete(client);
        },
      };
    }),
  );

  const unsubscribe = deps.bus.subscribe((event) => {
    const message = JSON.stringify(event);
    for (const client of clients) {
      if (shouldDeliver(event, client.user)) {
        try {
          client.ws.send(message);
        } catch {
          clients.delete(client);
        }
      }
    }
  });

  // Keep idle connections alive through proxies (Render/Railway close idle sockets).
  const keepAlive = setInterval(() => {
    for (const client of clients) {
      try {
        client.ws.send('{"type":"ping"}');
      } catch {
        clients.delete(client);
      }
    }
  }, 25_000);

  const server: ServerType = serve({ fetch: app.fetch, port });
  injectWebSocket(server);

  return {
    app,
    server,
    clientCount: () => clients.size,
    async close() {
      clearInterval(keepAlive);
      unsubscribe();
      for (const c of clients) c.ws.close();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    },
  };
}
