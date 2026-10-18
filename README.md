# Crumb & Craft Platform

Two Flutter apps (Android + iPhone) that share one backend and one Neon Postgres database, and stay in sync live.

```
CrumbAndCraft-Platform/
├── backend/               Node 22 + Hono API, Postgres (Neon), WebSocket live sync
├── packages/crumb_core/   Shared Dart code: models, API client, live sync, theme, widgets
├── apps/customer_app/     "Crumb & Craft" — customer app (Android + iOS)
├── apps/staff_app/        "C&C Kitchen" — staff & admin app (Android + iOS)
└── render.yaml            One-click deploy of the API to Render
```

## How sync works

```
 Customer app ──┐                         ┌── Staff / Admin app
                ├─ HTTPS (REST) ─► API ◄──┤
                └◄─ WebSocket /ws ─┘  │   └◄─ WebSocket /ws
                                      ▼
                              Neon Postgres
                     (LISTEN/NOTIFY "crumb_events")
```

Every change (an order placed, a status moved, stock or a batch timer changed, a menu edit, new prices) is written to Neon. In the same transaction it sends a Postgres `NOTIFY`. Each API instance relays that event over WebSockets to exactly the people who should see it:

| Event | Who receives it |
|---|---|
| Order created / updated | The customer who owns it, that branch's staff, all admins |
| Stock & batch timers, menu, prices, branches, promos | Everyone (guests included) |

The apps then re-fetch only what changed. They reconnect automatically, and they refresh again when brought back to the foreground. Because events travel through Postgres, sync also works when you run several API instances.

The apps never connect to Neon directly. The database password stays on the server.

## Features

**Customer app (Crumb & Craft)**
- **Onboarding:** pickup branch or delivery address, with a zone check by GPS or typed address against each branch's radius.
- **Browsing as a guest:** menu with categories, search, and free-from / dietary filters. Live "fresh out of the oven" countdowns, plus live stock ("3 left", sold out).
- **Product detail:** allergens, nutrition, baker's tips and special instructions.
- **Cake designer:** 5 steps (size, sponge, filling, frosting, message / eggless / piping style) with a live price. Designs can be saved.
- **Cart:** kept on the device, with a checkout that has:
  - live time windows (24 h notice for cakes, prep times)
  - promo codes and loyalty reward redemption
  - celebration add-ons and a server-checked total
- **Live order tracker:** pickup QR code, directions, and cancel while still confirmed.
- **Orders:** history with "order again".
- **Loyalty:** Baker's Dozen stamp card with the wax-seal animation.
- **Settings:** profile, password, light/dark theme, server address.

**Staff & Admin app (C&C Kitchen)**
- Sign-in for staff and admins only (customer accounts are refused).
- **Live orders board** with a sound + vibration alert on new orders and one-tap "next stage". Order detail includes:
  - calling the customer
  - a map for deliveries
  - a pickup-code check
  - cancelling with a reason (reserved stock goes back on the shelf)
- **Stock:** count the shelf, start an oven batch (customers see a countdown), batch out (adds to the shelf).
- **Staff** are locked to their branch. **Admins** can switch branch or see all branches, and get:
  - **Menu:** add/edit products, prices, photos, allergens, show/hide.
  - **Branches:** location and delivery radius.
  - **Promo codes:** percent, rupees off, free delivery, expiry.
  - **Business settings:** fees, free-delivery threshold, prep times, cake notice, loyalty rules, cake option prices, add-on prices.
  - **Team:** add staff/admins, assign branch, reset password, deactivate.
  - **Reports:** revenue, orders, average order, customers, revenue by day, by branch, best sellers. Reports update live.
- Tablet layout uses a side rail.

All money is whole rupees (PKR, "Rs"). Times are Asia/Karachi. Seed data is the three branches: F-7 Markaz, Saddar Rawalpindi and Bahria Town.

---

## 1. Create the Neon database (5 min)

1. Sign up at https://neon.tech, then create a project. Pick region **AWS Asia Pacific (Singapore)**, the closest to Pakistan.
2. Open **Connect** and copy two connection strings:
   - **Pooled** (host contains `-pooler`) → `DATABASE_URL`
   - **Direct** (turn "Connection pooling" off) → `DATABASE_URL_DIRECT`. This one is needed for live sync.

You don't need to create any tables. The API creates them and loads the menu and branches on first start.

## 2. Deploy the API (Render, ~10 min)

1. Push this folder to a GitHub repository.
2. In https://render.com, choose **New → Blueprint** and select the repo. Render reads `render.yaml`.
3. Fill in the environment variables when asked:

   | Variable | Value |
   |---|---|
   | `DATABASE_URL` | Neon pooled URL |
   | `DATABASE_URL_DIRECT` | Neon direct URL |
   | `JWT_SECRET` | 32+ random characters (e.g. output of `openssl rand -hex 32`) |
   | `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Your owner login for the staff app |
   | `DEMO_STAFF_PASSWORD` | Optional. Creates `staff.f7@`, `staff.saddar@`, `staff.bahria@crumbandcraft.pk` |

4. Deploy, then open `https://<your-service>.onrender.com/health`. It should show `{"ok":true,...}`.

> Use a paid instance ("Starter", set in `render.yaml`). Free instances sleep after inactivity, which drops the live connections.
> Railway, Fly.io or any VPS work too: `cd backend && npm ci && npm run build && npm start` (Docker: `backend/Dockerfile`).

## 3. Point the apps at your API

Choose either option.
- **At build time (recommended for release):** `--dart-define=API_URL=https://<your-service>.onrender.com`
- **At runtime:** Customer app → Profile → *Bakery server*. Staff app → login screen → *Server*, or Account → *Server*.

The APKs included in this delivery default to `http://10.0.2.2:8080`, which is a local API seen from the Android emulator. On a real phone, set the server address in the app first, or rebuild with `API_URL`.

## 4. Build the apps

Prerequisites: Flutter 3.35+ (built with 3.47.7).

```bash
# Android
cd apps/customer_app && flutter build apk --release --dart-define=API_URL=https://YOUR-API
cd apps/staff_app    && flutter build apk --release --dart-define=API_URL=https://YOUR-API
# Play Store bundle: flutter build appbundle ... (add your own signing key in android/app/build.gradle.kts)
```

### iPhone (needs a Mac with Xcode 16+)
```bash
cd apps/customer_app
flutter pub get && cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # Signing & Capabilities → choose your Apple team
flutter build ipa --dart-define=API_URL=https://YOUR-API
```
Repeat for `apps/staff_app`. Bundle IDs are `pk.crumbandcraft.crumbCustomer` and `pk.crumbandcraft.crumbStaff`; change them in Xcode if you like. Location permission text, local-network access for testing, and the tel/maps link schemes are already configured in `Info.plist`.

## 5. Run everything locally (development)

```bash
# Postgres anywhere (local Docker, or a Neon branch), then:
cd backend
cp .env.example .env        # fill in values; both DB URLs can be the same locally
npm install
npm run dev                 # http://localhost:8080 — migrates + seeds automatically

cd ../apps/customer_app && flutter run     # emulator reaches the API at 10.0.2.2:8080
cd ../apps/staff_app    && flutter run
```

On a physical phone on the same Wi-Fi, set the server to `http://<your-computer-IP>:8080`.

## Tests

```bash
cd backend && npm test   # 36 tests on a real Postgres. Needs a local server at
                         # postgres://postgres@127.0.0.1:55432 (see test/helpers.ts).
                         # Covers pricing, slots, stock races, hub isolation, cancel/restock,
                         # admin settings, WebSocket routing.

cd packages/crumb_core
API_URL=http://localhost:8080 flutter test test/live_api_test.dart
# End-to-end check of the shared Dart client against a running API:
# sign-up → quote → order → kitchen alert → status → customer live update
#   → oven batch → saved cake → admin report
```

## API reference (short)

| Area | Endpoints |
|---|---|
| Public | `GET /health` `/config` `/hubs` `/catalog?hubId=`, `POST /zone-check` |
| Auth | `POST /auth/register` `/auth/login`, `GET/PATCH /auth/me`, `POST /auth/password` |
| Customer | `/me/favorites`, `/me/saved-cakes`, `/me/loyalty`, `POST /orders/slots` `/orders/quote` `/orders`, `GET /orders` `/orders/:id`, `POST /orders/:id/cancel` |
| Staff | `GET /staff/orders?scope=active\|today\|all`, `/staff/orders/:id`, `POST /staff/orders/:id/status`, `GET /staff/stock`, `PATCH /staff/stock/:productId`, `POST …/start-batch` `…/batch-out` |
| Admin | `/admin/products` `/admin/hubs` `/admin/promos` `/admin/settings` `/admin/users` `/admin/reports?from&to&hubId` |
| Live | `wss://…/ws?token=<jwt>` (no token = guest: catalog/stock events only) |

Errors are always `{"error":{"code","message"}}`, and the messages are written to be shown to users.
