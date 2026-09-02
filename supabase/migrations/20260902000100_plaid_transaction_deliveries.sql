create table if not exists public.plaid_transaction_deliveries (
  item_id text not null references public.plaid_items(item_id) on delete cascade,
  transaction_id text not null,
  payload jsonb not null,
  first_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (item_id, transaction_id)
);

alter table public.plaid_transaction_deliveries enable row level security;

create index if not exists plaid_transaction_deliveries_item_id_transaction_id_idx
  on public.plaid_transaction_deliveries(item_id, transaction_id);
