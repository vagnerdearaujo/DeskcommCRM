@echo off
REM =====================================================================
REM Rollback do schema public do Supabase local (estrutura + dados).
REM Restaura o snapshot pre-migracao criado com pg_dump -Fc.
REM
REM USO:  restore-snapshot.cmd <arquivo.dump>
REM EX.:  restore-snapshot.cmd deskcomm-supabase-pre-migracao-2026-08-03.dump
REM
REM AVISO: a restauracao devolve o banco EXATAMENTE ao estado do snapshot.
REM Dados criados DEPOIS do snapshot sao perdidos. Os schemas auth,
REM storage e realtime nao sao tocados (as migrations so mexem em public).
REM
REM COBERTURA (por que estes drops manuais existem):
REM   pg_restore --clean --if-exists so droparia objetos que EXISTEM no dump.
REM   Objetos criados por migrations APOS o snapshot nao estao no dump e
REM   permaneceriam orfaos. Tabelas que ESTAO no dump (channel_sessions,
REM   messages, organizations, ai_agents, llm_calls...) sao dropadas e
REM   recriadas do zero pelo restore — colunas/constraints extras somem
REM   sozinhas. Objetos fora do dump precisam de drop manual:
REM     - 0088: tabela meta_templates (cascade cobre CHECK/indices/policy)
REM     - 0095: trigger trg_llm_calls_budget (em llm_calls)
REM     - 0096: trigger trg_seed_org_llm_defaults + fn_seed_org_llm_defaults
REM     - 0098: FK user_organizations_organization_id_fkey
REM =====================================================================
setlocal
if "%~1"=="" (
  echo USO: %~0 ^<arquivo.dump^>
  exit /b 1
)
set DUMP=%~f1
if not exist "%DUMP%" (
  echo Dump nao encontrado: %DUMP%
  exit /b 1
)

echo [1/6] Parando servicos que escrevem no banco...
docker stop deskcomm-srh deskcomm-agent-worker 2>nul

echo [2/6] Restaurando schema public de: %DUMP%
docker exec -i supabase_db_deskcomm-crm pg_restore -U postgres -d postgres -n public --clean --if-exists --no-owner < "%DUMP%"
if errorlevel 1 goto :erro

echo [3/6] Removendo objetos das migrations 0088/0095/0096/0098 que o dump nao conhece
docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "drop table if exists public.meta_templates cascade" -c "drop trigger if exists trg_llm_calls_budget on public.llm_calls" -c "drop trigger if exists trg_seed_org_llm_defaults on public.organizations" -c "drop function if exists public.fn_seed_org_llm_defaults()" -c "alter table public.user_organizations drop constraint if exists user_organizations_organization_id_fkey"
if errorlevel 1 goto :erro

echo [4/6] Validando estado pos-restore (levanta erro se sobrar objeto de migration)
docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "do $$ begin if exists (select 1 from information_schema.columns where table_schema='public' and table_name='channel_sessions' and column_name='provider') or exists (select 1 from information_schema.columns where table_schema='public' and table_name='messages' and column_name='template_name') or to_regclass('public.meta_templates') is not null or exists (select 1 from pg_constraint where conname='user_organizations_organization_id_fkey') then raise exception 'restore incompleto: objetos das migrations 0087-0098 ainda presentes'; end if; end $$;"
if errorlevel 1 goto :erro

echo [5/6] Recarregando schema no PostgREST
docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres -c "NOTIFY pgrst, 'reload schema';"
if errorlevel 1 goto :erro

echo [6/6] Reiniciando servicos parados...
docker start deskcomm-srh deskcomm-agent-worker 2>nul

echo Rollback concluido. Banco no estado do snapshot.
exit /b 0

:erro
echo FALHA no rollback. Verifique o erro acima.
docker start deskcomm-srh deskcomm-agent-worker 2>nul
exit /b 1
