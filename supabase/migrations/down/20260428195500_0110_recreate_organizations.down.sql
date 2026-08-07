-- =============================================================================
-- Down Migration 0096 — Desfaz organizations + channel_sessions
-- =============================================================================
-- Motivação: reverter a criação da tabela organizations e remover dados
-- inseridos para restaurar o estado anterior à migration 0096.
-- Ferramenta MANUAL: vive em migrations/down/ de propósito — o Supabase CLI
-- ignora subdiretórios, então um `supabase db push` nunca a executa. O
-- rollback oficial do banco é via snapshot (scripts/rollback.sh --db).
--
-- Uso:
--   docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres < supabase/migrations/down/20260428195500_0110_recreate_organizations.down.sql
-- =============================================================================

-- 1. Remover registros inseridos pela migration 0096
delete from public.channel_sessions
where waha_session_name = 'org_bb0f627e_d5d3bd';

-- 2. Remover organização default inserida
delete from public.organizations
where slug = 'deskcomm-local';

-- 3. Remover políticas RLS da organizations
drop policy if exists "organizations_tenant_isolation_select" on public.organizations;
drop policy if exists "organizations_platform_admin_all" on public.organizations;

-- 4. Desabilitar RLS
alter table public.organizations disable row level security;

-- 5. Remover helper function
drop function if exists public.fn_user_org_ids();

-- 6. Remover trigger
drop trigger if exists trg_organizations_touch on public.organizations;

-- 7. Remover tabela organizations
drop table if exists public.organizations;

-- 8. Remover fn_touch_updated_at (se nenhuma outra tabela usa)
-- CUIDADO: verificar dependências antes de executar!
-- drop function if exists public.fn_touch_updated_at();
