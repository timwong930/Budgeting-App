create table if not exists public.plaid_items (
  item_id text primary key,
  access_token_cipher text not null,
  institution_name text not null,
  transaction_cursor text,
  health text not null default 'connected',
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plaid_accounts (
  account_id text primary key,
  item_id text not null references public.plaid_items(item_id) on delete cascade,
  name text not null,
  type text,
  subtype text,
  current_balance double precision,
  available_balance double precision,
  credit_limit double precision,
  updated_at timestamptz not null default now()
);

create table if not exists public.plaid_sync_logs (
  id bigserial primary key,
  item_id text references public.plaid_items(item_id) on delete set null,
  event_type text not null,
  message text,
  created_at timestamptz not null default now()
);

create table if not exists public.plaid_import_mappings (
  plaid_id text primary key,
  plaid_item_id text references public.plaid_items(item_id) on delete cascade,
  local_model text not null,
  local_id uuid,
  import_status text not null default 'imported',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plaid_review_items (
  id uuid primary key default gen_random_uuid(),
  plaid_item_id text references public.plaid_items(item_id) on delete cascade,
  plaid_id text,
  review_type text not null,
  message text not null,
  payload jsonb not null default '{}'::jsonb,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.plaid_items enable row level security;
alter table public.plaid_accounts enable row level security;
alter table public.plaid_sync_logs enable row level security;
alter table public.plaid_import_mappings enable row level security;
alter table public.plaid_review_items enable row level security;

create index if not exists plaid_accounts_item_id_idx on public.plaid_accounts(item_id);
create index if not exists plaid_sync_logs_item_id_created_at_idx on public.plaid_sync_logs(item_id, created_at desc);
create index if not exists plaid_import_mappings_item_id_idx on public.plaid_import_mappings(plaid_item_id);
create index if not exists plaid_review_items_item_id_created_at_idx on public.plaid_review_items(plaid_item_id, created_at desc);
