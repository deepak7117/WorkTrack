-- =========================================================
-- WorkTrack — Admin Upgrade Migration
-- Run this if you already ran supabase-schema.sql before and just
-- want to add the new admin features (delete/edit user, audit log,
-- last-login tracking) without starting over. Safe to run once.
-- =========================================================

alter table public.profiles add column if not exists admin_notes text;
alter table public.profiles add column if not exists last_sign_in_at timestamptz;

create table if not exists public.admin_audit_log (
  id              uuid primary key default uuid_generate_v4(),
  admin_id        uuid not null references auth.users(id) on delete cascade,
  target_user_id  uuid references auth.users(id) on delete set null,
  action          text not null,
  details         jsonb default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

alter table public.admin_audit_log enable row level security;

drop policy if exists "audit_log_select_admin" on public.admin_audit_log;
create policy "audit_log_select_admin" on public.admin_audit_log
  for select using (public.is_admin());

drop policy if exists "audit_log_insert_admin" on public.admin_audit_log;
create policy "audit_log_insert_admin" on public.admin_audit_log
  for insert with check (admin_id = auth.uid() and public.is_admin());
