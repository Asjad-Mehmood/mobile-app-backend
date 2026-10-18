-- Crumb & Craft schema v1. All money is stored in whole rupees (integer).

create extension if not exists pgcrypto;

create table if not exists hubs (
  id                  text primary key,
  name                text not null,
  address             text not null,
  latitude            double precision not null,
  longitude           double precision not null,
  delivery_radius_km  double precision not null default 15,
  is_active           boolean not null default true,
  sort_order          integer not null default 0,
  created_at          timestamptz not null default now()
);

create table if not exists users (
  id             uuid primary key default gen_random_uuid(),
  email          text not null unique,
  password_hash  text not null,
  name           text not null,
  phone          text,
  role           text not null default 'customer' check (role in ('customer', 'staff', 'admin')),
  hub_id         text references hubs(id) on delete set null,  -- staff home branch (null = all)
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table if not exists products (
  id                   text primary key,
  name                 text not null,
  subtitle             text not null default '',
  description          text not null default '',
  crumb_notes          text,
  reheating_tip        text,
  base_price           integer not null check (base_price >= 0),
  category             text not null check (category in ('BREAD', 'PASTRY', 'CUSTOM_CAKE', 'COOKIE', 'BEVERAGE')),
  image_urls           jsonb not null default '[]',
  allergens            jsonb not null default '[]',
  dietary_tags         jsonb not null default '[]',
  bake_schedule        text not null default 'ALL_DAY'
                         check (bake_schedule in ('MORNING_BAKE', 'AFTERNOON_BAKE', 'ALL_DAY', 'PRE_ORDER_24H')),
  is_customizable_cake boolean not null default false,
  nutrition            jsonb,
  sort_order           integer not null default 0,
  is_listed            boolean not null default true,
  updated_at           timestamptz not null default now()
);

-- Live batch stock is per branch.
create table if not exists product_stock (
  product_id              text not null references products(id) on delete cascade,
  hub_id                  text not null references hubs(id) on delete cascade,
  remaining_batch_stock   integer not null default 0 check (remaining_batch_stock >= 0),
  current_batch_number    integer not null default 1,
  next_batch_ready_at     timestamptz,
  updated_at              timestamptz not null default now(),
  primary key (product_id, hub_id)
);

create table if not exists promo_codes (
  code          text primary key,
  description   text not null,
  type          text not null check (type in ('PERCENT_OFF', 'FIXED_OFF', 'FREE_DELIVERY')),
  value         integer not null default 0,
  min_spend     integer not null default 0,
  max_discount  integer,
  is_active     boolean not null default true,
  expires_at    timestamptz,
  created_at    timestamptz not null default now()
);

-- Business settings (fees, windows, cake options, add-ons) as one JSON document.
create table if not exists settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

create table if not exists orders (
  id                 text primary key,
  user_id            uuid not null references users(id),
  hub_id             text not null references hubs(id),
  status             text not null default 'ORDER_CONFIRMED'
                       check (status in ('ORDER_CONFIRMED', 'MIXING_AND_PROOFING', 'IN_THE_OVEN',
                                         'DECORATING_AND_COOLING', 'READY_OR_OUT_FOR_DELIVERY',
                                         'COMPLETED', 'CANCELLED')),
  fulfillment_type   text not null check (fulfillment_type in ('PICKUP', 'DELIVERY')),
  slot_date          date not null,
  slot_start_minute  integer not null,
  slot_end_minute    integer not null,
  slot_label         text not null,
  delivery_address   text,
  delivery_lat       double precision,
  delivery_lng       double precision,
  payment_method     text not null check (payment_method in ('CASH_ON_DELIVERY', 'CARD')),
  promo_code         text,
  pricing            jsonb not null,
  pickup_code        text,
  stamps_earned      integer not null default 0,
  loyalty_redeemed   boolean not null default false,
  stock_reserved     boolean not null default false,   -- same-day stock taken; restored on cancel
  status_history     jsonb not null default '[]',
  customer_note      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists orders_user_idx on orders (user_id, created_at desc);
create index if not exists orders_hub_status_idx on orders (hub_id, status, slot_date);

create table if not exists order_lines (
  id                    bigserial primary key,
  order_id              text not null references orders(id) on delete cascade,
  line_type             text not null default 'PRODUCT' check (line_type in ('PRODUCT', 'ADDON')),
  product_id            text not null,
  product_name          text not null,
  image_url             text,
  category              text,
  quantity              integer not null check (quantity > 0),
  unit_price            integer not null,
  customization         jsonb,
  special_instructions  text
);
create index if not exists order_lines_order_idx on order_lines (order_id);

create table if not exists favorites (
  user_id     uuid not null references users(id) on delete cascade,
  product_id  text not null references products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists saved_cakes (
  id             bigserial primary key,
  user_id        uuid not null references users(id) on delete cascade,
  product_id     text not null references products(id) on delete cascade,
  name           text not null,
  customization  jsonb not null,
  created_at     timestamptz not null default now()
);

create table if not exists schema_migrations (
  name        text primary key,
  applied_at  timestamptz not null default now()
);
