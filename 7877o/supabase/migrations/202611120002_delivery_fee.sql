-- Apply after 202611120001_checkout_requests.sql; review and test before deployment.
-- Checkout may supply an optional, validated delivery pin from migration 001.
begin;

alter table public.orders
  add column delivery_fee numeric,
  add column delivery_fee_status text not null default 'awaiting_quote',
  add column delivery_fee_revision integer not null default 0,
  add column if not exists delivery_latitude numeric,
  add column if not exists delivery_longitude numeric,
  add constraint orders_delivery_fee_valid check (
    delivery_fee is null or (delivery_fee >= 0 and delivery_fee <= 10000000 and delivery_fee = trunc(delivery_fee))
  ),
  add constraint orders_delivery_fee_state_valid check (
    (delivery_fee_status = 'awaiting_quote' and delivery_fee is null and delivery_fee_revision = 0)
    or (delivery_fee_status in ('offered', 'accepted', 'declined') and delivery_fee is not null and delivery_fee_revision > 0)
  );

-- Immutable to clients. Order IDs are retained even if an order is later deleted.
create table public.delivery_fee_events (
  id bigint generated always as identity primary key,
  order_id uuid not null,
  actor_id uuid not null,
  event text not null check (event in ('offered', 'accepted', 'declined')),
  revision integer not null,
  fee numeric not null,
  created_at timestamptz not null default now()
);
alter table public.delivery_fee_events enable row level security;
revoke all on public.delivery_fee_events from public, anon, authenticated;
grant select on public.delivery_fee_events to authenticated;
create policy delivery_fee_events_admin_read on public.delivery_fee_events
  for select to authenticated using (public.is_admin());

-- Function-owner context is the trusted boundary, not a client-settable GUC.
-- API roles must not own these functions or be able to SET ROLE to their owner.
create or replace function public.guard_order_delivery_fee_v1()
returns trigger language plpgsql security invoker set search_path = pg_catalog, public as $$
declare
  v_trusted boolean;
begin
  if tg_op = 'INSERT' then
    if new.delivery_fee is not null or new.delivery_fee_status <> 'awaiting_quote'
       or new.delivery_fee_revision <> 0 or new.status <> 'pending' then
      raise exception 'Orders must start pending and awaiting a delivery quote';
    end if;
    -- The orders_delivery_location_valid CHECK also covers direct inserts.
    return new;
  end if;

  -- Bind a quote to the original order owner and delivery destination.
  -- Location or address editing requires a separately reviewed migration.
  if new.user_id is distinct from old.user_id or new.address is distinct from old.address
     or new.delivery_latitude is distinct from old.delivery_latitude
     or new.delivery_longitude is distinct from old.delivery_longitude then
    raise exception 'Order owner and delivery location cannot be changed';
  end if;

  select current_user = pg_get_userbyid(p.proowner) into v_trusted
    from pg_proc p where p.oid = 'public.set_delivery_fee_v1(uuid,numeric)'::regprocedure;
  if (new.delivery_fee is distinct from old.delivery_fee
      or new.delivery_fee_status is distinct from old.delivery_fee_status
      or new.delivery_fee_revision is distinct from old.delivery_fee_revision)
     and not coalesce(v_trusted, false) then
    raise exception 'Delivery fee changes require the delivery fee RPCs';
  end if;

  if new.status is distinct from old.status then
    if old.status in ('cancelled', 'delivered') then
      raise exception 'A completed or cancelled order cannot be reopened';
    end if;
    if new.status in ('confirmed', 'processing', 'delivered')
       and new.delivery_fee_status <> 'accepted' then
      raise exception 'Customer must accept the current delivery fee before fulfillment';
    end if;
  end if;
  return new;
end $$;

create or replace function public.set_delivery_fee_v1(p_order_id uuid, p_fee numeric)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_order public.orders%rowtype;
  v_user uuid := auth.uid();
begin
  if v_user is null or not coalesce(public.is_admin(), false) then
    raise exception 'Admin access required';
  end if;
  if p_fee is null or not (p_fee >= 0 and p_fee <= 10000000 and p_fee = trunc(p_fee)) then
    raise exception 'Delivery fee must be a whole number from 0 to 10000000 UGX';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.status <> 'pending' then
    raise exception 'Delivery fee cannot be quoted for a completed or cancelled order';
  end if;
  if v_order.delivery_fee_revision = 2147483647 then raise exception 'Delivery fee revision limit reached'; end if;
  update public.orders set delivery_fee = p_fee, delivery_fee_status = 'offered',
    delivery_fee_revision = v_order.delivery_fee_revision + 1
    where id = p_order_id returning * into v_order;
  insert into public.delivery_fee_events(order_id, actor_id, event, revision, fee)
    values (v_order.id, v_user, 'offered', v_order.delivery_fee_revision, v_order.delivery_fee);
  return jsonb_build_object('order_id', v_order.id, 'delivery_fee', v_order.delivery_fee,
    'delivery_fee_status', v_order.delivery_fee_status, 'delivery_fee_revision', v_order.delivery_fee_revision);
end $$;

create or replace function public.respond_delivery_fee_v1(p_order_id uuid, p_revision integer, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_order public.orders%rowtype;
  v_user uuid := auth.uid();
  v_response text;
begin
  if v_user is null then raise exception 'Sign in to respond'; end if;
  if p_revision is null or p_accept is null then raise exception 'Revision and response are required'; end if;
  select * into v_order from public.orders where id = p_order_id and user_id = v_user for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.status <> 'pending' then
    raise exception 'This order is completed or cancelled';
  end if;
  if v_order.delivery_fee_revision <> p_revision or v_order.delivery_fee_status <> 'offered' then
    raise exception 'Delivery quote has changed or has already been answered';
  end if;
  v_response := case when p_accept then 'accepted' else 'declined' end;
  update public.orders set delivery_fee_status = v_response where id = p_order_id returning * into v_order;
  insert into public.delivery_fee_events(order_id, actor_id, event, revision, fee)
    values (v_order.id, v_user, v_response, v_order.delivery_fee_revision, v_order.delivery_fee);
  return jsonb_build_object('order_id', v_order.id, 'delivery_fee', v_order.delivery_fee,
    'delivery_fee_status', v_order.delivery_fee_status, 'delivery_fee_revision', v_order.delivery_fee_revision);
end $$;

-- Both SECURITY DEFINER RPCs must share the owner trusted by the trigger.
do $$
declare
  v_owner oid := (select proowner from pg_proc where oid = 'public.set_delivery_fee_v1(uuid,numeric)'::regprocedure);
  v_owner_name name := pg_get_userbyid(v_owner);
begin
  if v_owner <> (select proowner from pg_proc where oid = 'public.respond_delivery_fee_v1(uuid,integer,boolean)'::regprocedure) then
    raise exception 'Delivery fee RPC owners must match';
  end if;
  if pg_has_role('authenticated', v_owner, 'MEMBER') or pg_has_role('anon', v_owner, 'MEMBER') then
    raise exception 'API roles must not be members of the delivery fee RPC owner';
  end if;
  if not exists (select 1 from pg_class where oid = 'public.orders'::regclass and relrowsecurity) then
    raise exception 'orders RLS must be enabled';
  end if;
  -- The customer response RPC intentionally operates outside orders UPDATE RLS.
  if not exists (
    select 1 from pg_class c join pg_roles r on r.oid = v_owner
    where c.oid = 'public.orders'::regclass
      and (r.rolsuper or r.rolbypassrls or (c.relowner = v_owner and not c.relforcerowsecurity))
  ) then
    raise exception 'Delivery fee RPC owner % must be able to bypass orders RLS', v_owner_name;
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.orders'::regclass
      and tgname = 'orders_secure' and not tgisinternal and tgenabled in ('O', 'A')) then
    raise exception 'active orders_secure trigger is required';
  end if;
end $$;

create trigger orders_zz_delivery_guard before insert or update on public.orders
  for each row execute function public.guard_order_delivery_fee_v1();
revoke all on function public.guard_order_delivery_fee_v1() from public, anon, authenticated;
revoke all on function public.set_delivery_fee_v1(uuid, numeric) from public, anon, authenticated;
revoke all on function public.respond_delivery_fee_v1(uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.set_delivery_fee_v1(uuid, numeric) to authenticated;
grant execute on function public.respond_delivery_fee_v1(uuid, integer, boolean) to authenticated;

-- Table UPDATE grants override column revokes, and old column grants survive a
-- table revoke. Remove both. RLS still determines which rows an admin can edit.
revoke update on public.orders from public, anon, authenticated;
do $$
declare r record;
begin
  for r in select attname from pg_attribute where attrelid = 'public.orders'::regclass
           and attnum > 0 and not attisdropped loop
    execute format('revoke update (%I) on public.orders from public, anon, authenticated', r.attname);
  end loop;
end $$;
grant update (status) on public.orders to authenticated;

commit;
