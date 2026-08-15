-- =========================================================
-- WorkTrack — Supabase Schema
-- Run this once in your Supabase project's SQL Editor
-- (Project → SQL Editor → New query → paste → Run)
-- =========================================================

create extension if not exists "uuid-ossp";

-- =========================================================
-- 1. PROFILES  (one row per auth.users row — user or admin)
-- =========================================================
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  full_name      text,
  business_name  text,
  mobile         text,
  email          text,
  role           text not null default 'user'   check (role in ('user','admin')),
  status         text not null default 'active' check (status in ('active','suspended')),
  admin_notes    text,
  last_sign_in_at timestamptz,
  created_at     timestamptz not null default now()
);

-- =========================================================
-- 1b. ADMIN AUDIT LOG (every admin action, for accountability)
-- =========================================================
create table if not exists public.admin_audit_log (
  id              uuid primary key default uuid_generate_v4(),
  admin_id        uuid not null references auth.users(id) on delete cascade,
  target_user_id  uuid references auth.users(id) on delete set null,
  action          text not null,
  details         jsonb default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

-- =========================================================
-- 2. CUSTOMERS
-- =========================================================
create table if not exists public.customers (
  id         uuid primary key default uuid_generate_v4(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  company    text,
  mobile     text,
  whatsapp   text,
  email      text,
  address    text,
  gst        text,
  type       text default 'Individual',
  notes      text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- 3. WORK ORDERS
-- =========================================================
create table if not exists public.work_orders (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  customer_id       uuid references public.customers(id) on delete set null,
  title             text not null,
  description       text,
  date_received     date,
  due_date          date,
  assigned_person   text,
  priority          text default 'Medium',
  estimated_amount  numeric default 0,
  advance_received  numeric default 0,
  status            text default 'Pending',
  notes             text,
  created_at        timestamptz not null default now()
);

-- =========================================================
-- 4. PAYMENTS
-- =========================================================
create table if not exists public.payments (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  work_id     uuid references public.work_orders(id) on delete set null,
  date        date not null default current_date,
  amount      numeric not null,
  mode        text,
  ref         text,
  notes       text,
  created_at  timestamptz not null default now()
);

-- =========================================================
-- 5. EXPENSES
-- =========================================================
create table if not exists public.expenses (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  category    text,
  description text,
  amount      numeric not null,
  date        date not null default current_date,
  mode        text,
  notes       text,
  created_at  timestamptz not null default now()
);

-- =========================================================
-- 6. Helper: is the current user an admin?
--    (security definer so it can read profiles even though
--     profiles itself is protected by RLS)
-- =========================================================
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- =========================================================
-- 7. Auto-create a profile row whenever someone signs up
--    (reads full_name / business_name / mobile passed in
--     supabase.auth.signUp({ options: { data: {...} } }))
-- =========================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, full_name, business_name, mobile, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'business_name', ''),
    coalesce(new.raw_user_meta_data->>'mobile', ''),
    new.email,
    'user'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =========================================================
-- 8. Row Level Security
-- =========================================================
alter table public.profiles        enable row level security;
alter table public.customers       enable row level security;
alter table public.work_orders     enable row level security;
alter table public.payments        enable row level security;
alter table public.expenses        enable row level security;
alter table public.admin_audit_log enable row level security;

-- ---- profiles ----
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin" on public.profiles
  for update using (id = auth.uid() or public.is_admin());

-- ---- customers ----
drop policy if exists "customers_all_own_or_admin" on public.customers;
create policy "customers_all_own_or_admin" on public.customers
  for all using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ---- work_orders ----
drop policy if exists "work_orders_all_own_or_admin" on public.work_orders;
create policy "work_orders_all_own_or_admin" on public.work_orders
  for all using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ---- payments ----
drop policy if exists "payments_all_own_or_admin" on public.payments;
create policy "payments_all_own_or_admin" on public.payments
  for all using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ---- expenses ----
drop policy if exists "expenses_all_own_or_admin" on public.expenses;
create policy "expenses_all_own_or_admin" on public.expenses
  for all using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ---- admin_audit_log ----
-- Only admins can read the log. Admins can insert entries recording
-- their own actions (used for actions taken directly with the anon
-- key, e.g. editing a profile). Privileged actions like deleting a
-- user go through the admin-actions Edge Function, which uses the
-- service role key and bypasses RLS entirely to insert its own entries.
drop policy if exists "audit_log_select_admin" on public.admin_audit_log;
create policy "audit_log_select_admin" on public.admin_audit_log
  for select using (public.is_admin());

drop policy if exists "audit_log_insert_admin" on public.admin_audit_log;
create policy "audit_log_insert_admin" on public.admin_audit_log
  for insert with check (admin_id = auth.uid() and public.is_admin());

-- =========================================================
-- 9. Make the FIRST account you sign up an admin
--    Run this manually, once, after your first signup —
--    replace the email with the account you want as admin.
-- =========================================================
-- update public.profiles set role = 'admin' where email = 'you@example.com';
