-- Additive checkout migration; review and apply manually AFTER full_setup.sql.
-- No payment is initiated. The existing secure_order trigger remains responsible
-- for recalculating prices, checking stock and setting status to pending.
begin;

alter table public.orders
  add column if not exists preferred_delivery_date date,
  add column if not exists checkout_request_id uuid,
  add column if not exists checkout_request_hash text;
create unique index if not exists orders_user_checkout_request_unique
  on public.orders (user_id, checkout_request_id)
  where checkout_request_id is not null;

-- Refuse to install against an incompatible or unprotected orders table.
do $$
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = 'orders' and c.relrowsecurity) then
    raise exception 'orders RLS must be enabled before checkout migration';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.orders'::regclass
                 and tgname = 'orders_secure' and not tgisinternal and tgenabled in ('O', 'A')) then
    raise exception 'active orders_secure trigger is required';
  end if;
end $$;

-- SECURITY INVOKER deliberately preserves existing orders INSERT/SELECT RLS.
-- Advisory lock + request key lets the same customer safely retry after a lost
-- response. A changed payload cannot silently resolve to a different order.
create or replace function public.place_checkout_order_v1(
  p_request_id uuid, p_phone text, p_address text, p_note text,
  p_preferred_date date, p_items jsonb
) returns jsonb
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_hash text;
  v_order public.orders%rowtype;
begin
  if v_user is null then raise exception 'Sign in to place an order'; end if;
  if p_request_id is null or nullif(btrim(p_phone), '') is null
     or nullif(btrim(p_address), '') is null then
    raise exception 'Phone, address and request ID are required';
  end if;
  if char_length(p_phone) > 80 or char_length(p_address) > 500 or char_length(coalesce(p_note, '')) > 1000 then
    raise exception 'One or more checkout fields are too long';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Your cart is empty';
  end if;
  if not exists (select 1 from pg_class where oid = 'public.orders'::regclass and relrowsecurity)
     or not exists (select 1 from pg_trigger where tgrelid = 'public.orders'::regclass
                    and tgname = 'orders_secure' and not tgisinternal and tgenabled in ('O', 'A')) then
    raise exception 'Checkout is unavailable: order safeguards are not active';
  end if;
  v_hash := md5(jsonb_build_object('phone', btrim(p_phone), 'address', btrim(p_address),
    'note', coalesce(btrim(p_note), ''), 'date', p_preferred_date, 'items', p_items)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || p_request_id::text, 0));
  select * into v_order from public.orders where user_id = v_user and checkout_request_id = p_request_id;
  if found then
    if v_order.checkout_request_hash is distinct from v_hash then
      raise exception 'This checkout attempt has different details. Check My Orders before starting another order.';
    end if;
    return jsonb_build_object('id', v_order.id, 'status', v_order.status, 'total', v_order.total,
                              'preferred_delivery_date', v_order.preferred_delivery_date);
  end if;
  insert into public.orders (user_id, customer_name, phone, address, note, payment_method, items, total, status,
                             preferred_delivery_date, checkout_request_id, checkout_request_hash)
  values (v_user, coalesce(nullif(auth.jwt()->'user_metadata'->>'full_name', ''), 'Customer'), btrim(p_phone), btrim(p_address), coalesce(btrim(p_note), ''), 'Cash on delivery',
          p_items, 0, 'pending', p_preferred_date, p_request_id, v_hash)
  returning * into v_order;
  return jsonb_build_object('id', v_order.id, 'status', v_order.status, 'total', v_order.total,
                            'preferred_delivery_date', v_order.preferred_delivery_date);
end $$;
revoke all on function public.place_checkout_order_v1(uuid, text, text, text, date, jsonb) from public, anon;
grant execute on function public.place_checkout_order_v1(uuid, text, text, text, date, jsonb) to authenticated;
commit;
