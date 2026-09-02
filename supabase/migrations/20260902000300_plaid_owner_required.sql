do $$
begin
  if exists (select 1 from public.plaid_items where owner_user_id is null) then
    raise exception 'Cannot enforce Plaid ownership while unowned Plaid Items remain';
  end if;
end
$$;

alter table public.plaid_items
  alter column owner_user_id set not null;
