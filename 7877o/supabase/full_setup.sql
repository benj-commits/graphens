-- Run this whole file in Supabase > SQL Editor.

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text, phone text,
  role text not null default 'customer',
  created_at timestamptz default now()
);

create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, full_name, phone)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'phone');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create function is_admin() returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin')
$$;

create table products (
  id uuid primary key default gen_random_uuid(),
  name text not null, category text, price numeric default 0, stock int default 0,
  description text, images text[] default '{}', active boolean default true,
  created_at timestamptz default now()
);
create table projects (
  id uuid primary key default gen_random_uuid(),
  title text not null, category text, price_from numeric default 0, status text,
  description text, images text[] default '{}', active boolean default true,
  created_at timestamptz default now()
);
create table orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null,
  customer_name text, phone text, address text, note text, payment_method text,
  items jsonb not null, total numeric not null,
  status text not null default 'pending',
  created_at timestamptz default now()
);
create table messages (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references auth.users not null,
  sender_id uuid references auth.users not null,
  is_admin boolean default false,
  body text not null,
  created_at timestamptz default now()
);
create table feedback (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references projects on delete cascade,
  user_id uuid references auth.users not null,
  customer_name text, rating int, comment text,
  created_at timestamptz default now()
);

alter table profiles enable row level security;
alter table products enable row level security;
alter table projects enable row level security;
alter table orders enable row level security;
alter table messages enable row level security;
alter table feedback enable row level security;

create policy "profile read" on profiles for select using (id = auth.uid() or is_admin());
create policy "profile admin write" on profiles for update using (is_admin());

create policy "products read" on products for select using (active or is_admin());
create policy "products admin" on products for all using (is_admin()) with check (is_admin());
create policy "projects read" on projects for select using (active or is_admin());
create policy "projects admin" on projects for all using (is_admin()) with check (is_admin());

create policy "orders insert" on orders for insert with check (user_id = auth.uid());
create policy "orders read" on orders for select using (user_id = auth.uid() or is_admin());
create policy "orders admin update" on orders for update using (is_admin());

create policy "messages read" on messages for select using (customer_id = auth.uid() or is_admin());
create policy "messages insert" on messages for insert with check (
  (customer_id = auth.uid() and sender_id = auth.uid() and is_admin = false) or is_admin()
);

create policy "feedback read" on feedback for select using (auth.uid() is not null);
create policy "feedback insert" on feedback for insert with check (user_id = auth.uid());
create policy "feedback admin delete" on feedback for delete using (is_admin());

alter publication supabase_realtime add table products, projects, orders, messages, feedback;

-- Image storage
insert into storage.buckets (id, name, public) values ('media', 'media', true);
create policy "media public read" on storage.objects for select using (bucket_id = 'media');
create policy "media admin write" on storage.objects for insert with check (bucket_id = 'media' and is_admin());
create policy "media admin delete" on storage.objects for delete using (bucket_id = 'media' and is_admin());

-- After you register your own account in the app, make it the admin:
-- update profiles set role = 'admin' where id = (select id from auth.users where email = 'YOUR_EMAIL');
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
