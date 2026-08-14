-- =============================================================================
-- ROLLBACK — alinhamento do histórico supabase_migrations.schema_migrations
-- Data: 2026-08-03
--
-- O que foi feito (o que este arquivo reverte):
--   7 versões foram REGISTRADAS no histórico do Supabase CLI, porque as
--   migrations correspondentes já tinham sido aplicadas manualmente no banco
--   (via docker exec psql, 2026-08-03 15:47–17:02), mas sem registrar a versão.
--   Verificado por probe SQL: todos os objetos/efeitos existem (2026-08-03).
--
--   Versões registradas:
--     20260428195500  0096_recreate_organizations
--     20260727120000  0087_channel_provider
--     20260728120000  0088_meta_templates
--     20260729120000  0091_message_type_template
--     20260730180000  0095_budget_conta_llm_calls
--     20260730220000  0097_rag_threshold_calibrado
--     20260803000000  0098_user_organizations_organization_fk
--
-- Rollback: remover as versões do histórico. NENHUM dado de negócio é tocado —
-- é bookkeeping do CLI. Após o rollback, o CLI voltará a considerar essas
-- migrations "pendentes" e um futuro `supabase db push` as reaplicará
-- (idempotente, sem quebra).
--
-- Uso:
--   docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres < backups/rollback-alinhar-historico-2026-08-03.sql
-- =============================================================================

begin;

delete from supabase_migrations.schema_migrations
where version in (
  '20260428195500',
  '20260727120000',
  '20260728120000',
  '20260729120000',
  '20260730180000',
  '20260730220000',
  '20260803000000'
);

commit;
