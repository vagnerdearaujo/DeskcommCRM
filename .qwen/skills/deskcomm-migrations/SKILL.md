---
name: deskcomm-migrations
description: Opera migrations e schema do banco Supabase local do DeskComm com segurança — snapshot completo (pg_dump -Fc), aplicação com ON_ERROR_STOP, verificação pós-migração e script de restore pronto. Use para aplicar migrations novas, reaplicar, auditar schema_migrations x arquivos, criar migrations seguindo a doutrina tripla ou resolver colisão de numeração. Segue a DOUTRINA (.qwen/DESKCOMM-DOUTRINA.md), especialmente §3 (snapshot+rollback) e §6 (política fork×upstream).
---

# Migrations DeskComm — operação segura

**Leia `.qwen/DESKCOMM-DOUTRINA.md` primeiro.** Aqui valem sobretudo: §3 snapshot+rollback (o usuário pergunta explicitamente se existe), §6 doutrina tripla + fork×upstream, §2 nunca destruir sem 3 opções validadas.

## Contexto fixo do projeto

- Stacks locais: main (api 54321, db 54322, studio 54323) e dev (54421/54422/54423). `NEXT_PUBLIC_SUPABASE_URL` aponta para qual stack está sendo testada.
- Doutrina tripla de uma migration: (1) arquivo versionado `supabase/migrations/<timestamp>_<NNNN>_<slug>.sql`, (2) apêndice correspondente no `supabase/baseline.sql`, (3) linha em `supabase/migrations/MANIFEST.md`.
- Convenções: `down/` + fila alfabética + CLI aplica `.down.sql` da raiz (ver memória do projeto "Convenções de migrations do Deskcomm").
- Timestamp = identidade no `supabase_migrations.schema_migrations`. Renumerar NNNN NÃO muda timestamp → nenhum banco re-aplica.
- Catraca: `npx vitest run tests/unit/manifest-x-migrations.test.ts` (6 casos). **Nunca** readicionar exceção em DIVERGENCIAS_CONHECIDAS.

## Fluxo de aplicação

### 1. Pré-condições
1. Stack Up: `supabase status` (Kong healthy, 54321 respondendo). Se Kong poluído/morto, usar a skill `deskcomm-stack-local` para recuperar ANTES.
2. Conferir quais migrations ainda não estão aplicadas: comparar arquivos em `supabase/migrations/` com `supabase_migrations.schema_migrations` (via psql na porta certa).

### 2. Snapshot (obrigatório antes de QUALQUER mudança)
3. `pg_dump -Fc -d postgresql://postgres:postgres@127.0.0.1:<db_port>/postgres -f <dir-backup>/snapshot-<data>-<hora>.dump` (timestamp no nome).
4. Gravar o caminho num checkpoint `.qwen/state/ultima-migracao.json` junto com: migrations a aplicar, ordem, passo atual.

### 3. Aplicar
5. Aplicar com `ON_ERROR_STOP` (via CLI do repo ou `psql --set ON_ERROR_STOP=1 -f <arquivo>`), uma a uma, na ordem do timestamp.
6. Entre cada migration: conferir exit code e `schema_migrations` atualizado.

### 4. Verificar
7. Catraca: `npx vitest run tests/unit/manifest-x-migrations.test.ts` → 6/6.
8. Verificação funcional mínima (conforme a migration): consulta às tabelas/funções novas, `notify pgrst, 'reload schema'` quando aplicável, teste da rota se houver.

### 5. Restore (se algo der errado)
9. Script documentado no checkpoint: `pg_restore --clean -d postgresql://postgres:postgres@127.0.0.1:<db_port>/postgres <snapshot>.dump` + reiniciar stack se necessário (`supabase stop` + `supabase start` — `start` sozinho NÃO recria container removido).

## Criar migration nova (doutrina tripla)
1. Número livre NNNN (listar `supabase/migrations/` e o teste da catraca valida duplicados).
2. Timestamp novo (nunca reutilizar o de uma migration já aplicada).
3. Criar os 3 artefatos (arquivo + apêndice baseline + linha MANIFEST com descrição do PORQUÊ, no estilo das existentes).
4. Catraca verde antes de aplicar.

## Rollback

| Situação | Ação |
|---|---|
| Aplicação falhou no meio | Restore do snapshot pré-mudança |
| Migration já aplicada e precisa desfazer | `.down.sql` via CLI (da raiz) |
| Banco inconsistente pós-falha | Inspecionar schema_migrations × arquivos ANTES de qualquer ação; 3 caminhos |

## Limitações

- Nenhum DROP/DELETE/remodelagem sem 3 opções validadas + aprovação do usuário.
- Não "conserta" migration já aplicada: documenta o desvio e propõe nova migration.
- Não roda em produção/VPS (isso é da skill de deploy, com separação explícita).
