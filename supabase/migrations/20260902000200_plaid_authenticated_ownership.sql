alter table public.plaid_items
  add column if not exists owner_user_id uuid references auth.users(id) on delete cascade;

create index if not exists plaid_items_owner_user_id_idx
  on public.plaid_items(owner_user_id);

-- Plaid records are backend-managed. Keep direct table privileges closed while
-- still defining owner-scoped RLS as defense in depth if client grants are ever added.
revoke all on table public.plaid_items from anon, authenticated;
revoke all on table public.plaid_accounts from anon, authenticated;
revoke all on table public.plaid_sync_logs from anon, authenticated;
revoke all on table public.plaid_import_mappings from anon, authenticated;
revoke all on table public.plaid_review_items from anon, authenticated;
revoke all on table public.plaid_transaction_deliveries from anon, authenticated;

alter table public.plaid_items enable row level security;
alter table public.plaid_accounts enable row level security;
alter table public.plaid_sync_logs enable row level security;
alter table public.plaid_import_mappings enable row level security;
alter table public.plaid_review_items enable row level security;
alter table public.plaid_transaction_deliveries enable row level security;

drop policy if exists plaid_items_owner_access on public.plaid_items;
create policy plaid_items_owner_access
  on public.plaid_items
  for all
  to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

drop policy if exists plaid_accounts_owner_access on public.plaid_accounts;
create policy plaid_accounts_owner_access
  on public.plaid_accounts
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_accounts.item_id
        and item.owner_user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_accounts.item_id
        and item.owner_user_id = (select auth.uid())
    )
  );

drop policy if exists plaid_sync_logs_owner_access on public.plaid_sync_logs;
create policy plaid_sync_logs_owner_access
  on public.plaid_sync_logs
  for all
  to authenticated
  using (
    item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_sync_logs.item_id
        and item.owner_user_id = (select auth.uid())
    )
  )
  with check (
    item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_sync_logs.item_id
        and item.owner_user_id = (select auth.uid())
    )
  );

drop policy if exists plaid_import_mappings_owner_access on public.plaid_import_mappings;
create policy plaid_import_mappings_owner_access
  on public.plaid_import_mappings
  for all
  to authenticated
  using (
    plaid_item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_import_mappings.plaid_item_id
        and item.owner_user_id = (select auth.uid())
    )
  )
  with check (
    plaid_item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_import_mappings.plaid_item_id
        and item.owner_user_id = (select auth.uid())
    )
  );

drop policy if exists plaid_review_items_owner_access on public.plaid_review_items;
create policy plaid_review_items_owner_access
  on public.plaid_review_items
  for all
  to authenticated
  using (
    plaid_item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_review_items.plaid_item_id
        and item.owner_user_id = (select auth.uid())
    )
  )
  with check (
    plaid_item_id is not null
    and exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_review_items.plaid_item_id
        and item.owner_user_id = (select auth.uid())
    )
  );

drop policy if exists plaid_transaction_deliveries_owner_access on public.plaid_transaction_deliveries;
create policy plaid_transaction_deliveries_owner_access
  on public.plaid_transaction_deliveries
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_transaction_deliveries.item_id
        and item.owner_user_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.plaid_items item
      where item.item_id = plaid_transaction_deliveries.item_id
        and item.owner_user_id = (select auth.uid())
    )
  );
