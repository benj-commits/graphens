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
  delivery_fee numeric not null default 0,
  delivery_fee_confirmed boolean not null default false,
  delivery_fee_status text not null default 'pending_customer_confirmation',
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
alter table orders add constraint orders_status_chk check (status in ('pending','confirmed','processing','delivered','cancelled'));
alter table orders add constraint orders_total_chk check (total >= 0);
alter table orders add constraint orders_delivery_fee_chk check (delivery_fee >= 0);
alter table feedback add constraint feedback_rating_chk check (rating between 1 and 5);
alter table feedback add constraint feedback_len_chk check (char_length(coalesce(comment, '')) <= 1000);
alter table messages add constraint messages_len_chk check (char_length(body) between 1 and 2000);
