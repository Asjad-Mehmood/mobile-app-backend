import { EventEmitter } from 'node:events';
import postgres from 'postgres';
import type { Db } from '../db.js';

export type AppEvent =
  | { type: 'catalog.updated' }
  | { type: 'settings.updated' }
  | { type: 'hubs.updated' }
  | { type: 'promos.updated' }
  | { type: 'stock.updated'; hubId: string; productIds: string[] }
  | { type: 'order.created' | 'order.updated'; orderId: string; hubId: string; userId: string; status: string };

const CHANNEL = 'crumb_events';

/**
 * Cross-instance event bus built on Postgres LISTEN/NOTIFY.
 *
 * `publish` inside a transaction is delivered only when that transaction commits, so apps
 * never hear about an order that was rolled back. Neon: LISTEN needs the *direct*
 * (non-pooled) connection string. Without a listen URL the bus works in-process only.
 */
export class EventBus {
  private readonly emitter = new EventEmitter();
  private listener: postgres.Sql | null = null;
  private listening = false;

  constructor(
    private readonly sql: Db,
    private readonly listenUrl?: string,
  ) {
    this.emitter.setMaxListeners(0);
  }

  async start(): Promise<void> {
    if (!this.listenUrl) return;
    try {
      this.listener = postgres(this.listenUrl, { max: 1, onnotice: () => {} });
      await this.listener.listen(CHANNEL, (payload) => {
        try {
          this.emitter.emit('event', JSON.parse(payload) as AppEvent);
        } catch {
          /* ignore malformed payloads */
        }
      });
      this.listening = true;
    } catch (e) {
      console.warn('[events] LISTEN unavailable, falling back to in-process events:', (e as Error).message);
      await this.listener?.end({ timeout: 1 }).catch(() => {});
      this.listener = null;
    }
  }

  async publish(event: AppEvent, db: Db = this.sql): Promise<void> {
    if (this.listening) {
      await db`select pg_notify(${CHANNEL}, ${JSON.stringify(event)})`;
    } else {
      queueMicrotask(() => this.emitter.emit('event', event));
    }
  }

  subscribe(fn: (e: AppEvent) => void): () => void {
    this.emitter.on('event', fn);
    return () => this.emitter.off('event', fn);
  }

  async stop(): Promise<void> {
    this.emitter.removeAllListeners();
    await this.listener?.end({ timeout: 1 });
  }
}
