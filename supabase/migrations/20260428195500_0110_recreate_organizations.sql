-- =============================================================================
-- Migration 0096 — Recria organizations (migration 0001 era stub) + channel_session
-- =============================================================================
-- Motivação: a migration 0001_platform_base.sql continha apenas SELECT 1 (stub),
-- então a tabela organizations nunca foi criada no banco local. As FKs para ela
-- também não foram aplicadas (channel_sessions não tem FK p/ organizations).
-- Esta migration cria organizations e insere o registro necessário para
-- reconectar à sessão WAHA existente.
-- =============================================================================

-- 1. Extensions
create extension if not exists "citext";

-- 2. Helper fn_touch_updated_at (se não existir)
create or replace function public.fn_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- 2. Organizations
create table if not exists public.organizations (
  id              uuid primary key default gen_random_uuid(),
  slug            citext not null unique,
  legal_name      text not null,
  display_name    text not null,
  cnpj            text unique,
  status          text not null default 'active'
                  check (status in ('active','suspended','redacted','archived')),
  timezone        text not null default 'America/Sao_Paulo',
  locale          text not null default 'pt-BR',
  rate_limit_rps  integer not null default 100,
  ai_budget_cents bigint,
  media_retention_days integer not null default 365,
  settings        jsonb not null default '{}'::jsonb,
  dpo_email       citext,
  privacy_policy_url text,
  onboarded_at    timestamptz,
  suspended_at    timestamptz,
  redacted_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references auth.users(id) on delete set null
);

create trigger trg_organizations_touch
  before update on public.organizations
  for each row execute function public.fn_touch_updated_at();

-- 3. Helper fn_user_org_ids (se não existir)
create or replace function public.fn_user_org_ids()
returns setof uuid
language sql stable
security definer
set search_path = public
as $$
  select organization_id
  from public.user_organizations
  where user_id = auth.uid()
    and revoked_at is null;
$$;

-- 4. Enable RLS
alter table public.organizations enable row level security;

create policy "organizations_tenant_isolation_select"
  on public.organizations for select
  using (id in (select public.fn_user_org_ids()));

create policy "organizations_platform_admin_all"
  on public.organizations for all
  using (exists (select 1 from public.platform_admins where user_id = auth.uid() and revoked_at is null))
  with check (exists (select 1 from public.platform_admins where user_id = auth.uid() and revoked_at is null));

-- 5. Inserir organização default para dev local
insert into public.organizations (slug, legal_name, display_name, timezone, locale, onboarded_at)
values ('deskcomm-local', 'DeskcommCRM Desenvolvimento', 'DeskcommCRM Dev', 'America/Sao_Paulo', 'pt-BR', now())
on conflict (slug) do nothing;
