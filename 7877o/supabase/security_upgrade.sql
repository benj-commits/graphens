-- Graphen Bags: security hardening. Run ONCE, after schema.sql (full_setup.sql already includes both).

-- 1) Admin check: if an admin has turned on 2-factor, the database itself demands the 2FA-verified session.
create or replace function is_admin() returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  and (
    coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
    or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified')
  );
$$;

-- 2) Nobody can promote themselves to admin through the API.
create or replace function protect_role() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role and auth.uid() is not null then
    raise exception 'Role can only be changed from the Supabase SQL Editor';
  end if;
  return new;
end $$;
create trigger profiles_protect_role before update on profiles for each row execute function protect_role();

-- 3) Data sanity rules
alter table products add constraint products_price_chk check (price >= 0);
alter table products add constraint products_stock_chk check (stock >= 0);
alter table projects add constraint projects_price_chk check (price_from >= 0);
alter table orders   add constraint orders_status_chk check (status in ('pending','confirmed','processing','delivered','cancelled'));
alter table orders   add constraint orders_total_chk check (total >= 0);
alter table feedback add constraint feedback_rating_chk check (rating between 1 and 5);
alter table feedback add constraint feedback_len_chk check (char_length(coalesce(comment, '')) <= 1000);
alter table messages add constraint messages_len_chk check (char_length(body) between 1 and 2000);

-- 4) Price tampering protection: the server recalculates every order from the real product prices,
--    checks stock, reduces stock, and forces new orders to start as "pending".
create or replace function secure_order() returns trigger language plpgsql security definer set search_path = public as $$
declare it jsonb; p record; q int; fixed jsonb := '[]'::jsonb; t numeric := 0;
begin
  if auth.uid() is null then return new; end if;
  if jsonb_typeof(new.items) <> 'array' or jsonb_array_length(new.items) = 0 then
    raise exception 'Your cart is empty';
  end if;
  for it in select jsonb_array_elements(new.items) loop
    select * into p from products where id = (it->>'id')::uuid and active;
    if not found then raise exception 'An item in your cart is no longer available'; end if;
    q := greatest(coalesce((it->>'qty')::int, 1), 1);
    if p.stock < q then raise exception 'Not enough stock for %', p.name; end if;
    update products set stock = stock - q where id = p.id;
    fixed := fixed || jsonb_build_object('id', p.id, 'name', p.name, 'price', p.price, 'qty', q);
    t := t + p.price * q;
  end loop;
  new.items := fixed; new.total := t; new.status := 'pending';
  return new;
end $$;
create trigger orders_secure before insert on orders for each row execute function secure_order();

create or replace function restore_stock() returns trigger language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    for it in select jsonb_array_elements(new.items) loop
      update products set stock = stock + (it->>'qty')::int where id = (it->>'id')::uuid;
    end loop;
  end if;
  return new;
end $$;
create trigger orders_restore after update on orders for each row execute function restore_stock();

-- 5) Activity log: every admin change is recorded (shown on the admin website under "Activity").
create table audit_log (
  id bigint generated always as identity primary key,
  user_id uuid, action text, table_name text, row_id text, label text,
  created_at timestamptz default now()
);
alter table audit_log enable row level security;
create policy "audit read" on audit_log for select using (is_admin());

create or replace function log_change() returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb; rid text;
begin
  if not is_admin() then return null; end if;
  if tg_op = 'DELETE' then r := to_jsonb(old); rid := old.id::text; else r := to_jsonb(new); rid := new.id::text; end if;
  insert into audit_log(user_id, action, table_name, row_id, label)
  values (auth.uid(), tg_op, tg_table_name, rid, coalesce(r->>'name', r->>'title', r->>'status'));
  return null;
end $$;
create trigger audit_products after insert or update or delete on products for each row execute function log_change();
create trigger audit_projects after insert or update or delete on projects for each row execute function log_change();
create trigger audit_orders   after update or delete on orders   for each row execute function log_change();
create trigger audit_feedback after delete on feedback for each row execute function log_change();

-- 6) Photo uploads: images only, max 5 MB
update storage.buckets set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'] where id = 'media';
