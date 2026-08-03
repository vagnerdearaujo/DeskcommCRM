-- 0098 — FK user_organizations.organization_id → organizations.id
--
-- O fork criou organizations na migration 0096 (recreate) SEM as FKs que o
-- baseline do upstream declara — o 0001 do upstream era stub e a tabela nunca
-- foi criada com as constraints de relacionamento. Consequência concreta:
-- o PostgREST não montava o embed organizations(display_name) dentro de
-- loadAuthUser e o /app quebrava com 500:
--
--   auth_permissions_unavailable: Could not find a relationship between
--   'user_organizations' and 'organizations' in the schema cache (PGRST200)
--
-- Alinhado à definição do upstream (supabase/baseline.sql): ON DELETE CASCADE.
-- Idempotente: a FK já foi aplicada manualmente no dev em 2026-08-03, mas não
-- consta em supabase_migrations.schema_migrations — sem o guard, um futuro
-- `supabase db push` falharia com "constraint already exists".

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'user_organizations_organization_id_fkey'
      and conrelid = 'public.user_organizations'::regclass
  ) then
    alter table public.user_organizations
      add constraint user_organizations_organization_id_fkey
      foreign key (organization_id) references public.organizations(id)
      on delete cascade;
  end if;
end $$;

-- PostgREST cacheia o schema; sem o reload ele continua sem enxergar a FK e o
-- PGRST200 volta até um restart do container.
notify pgrst, 'reload schema';
