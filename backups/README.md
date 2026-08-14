# DeskcommCRM — Banco: DR, bootstrap e migrations

> Documento canônico (2026-08-05). Resolve e formaliza as descobertas técnicas 1–3:
> modelo de bootstrap, pares de timestamp e usuário correto de restore.

---

## 1. Modelo de bootstrap (como um banco nasce)

**O banco NUNCA nasce de `supabase start`/`supabase db reset` com migrations.**
Ele nasce de **`supabase/baseline.sql` + restore de dump** (pg_restore de um `.dump`).

Por quê — a pasta `supabase/migrations/` é um **espelho de registros**, não uma
história reproduzível:

- **10 migrations são stubs `SELECT 1`** (0001–0009 e 0013) — o schema real vive no `baseline.sql`.
- **`0096_recreate_organizations` referencia `public.user_organizations`**, tabela que
  **nenhuma migration cria** — num reset fresh, o `CREATE OR REPLACE FUNCTION
  fn_user_org_ids()` falha no parse (relação inexistente). Não é bug de RLS nem de
  retorno; é dependência do baseline.
- **4 pares de timestamp idênticos do upstream** colidem na PK de `version` de
  `supabase_migrations.schema_migrations` (0034/0038, 0042/0043, 0054/0055, 0062/0064).
  Só o primeiro de cada par fica registrado; o SQL dos 4 órfãos já está no schema
  (via baseline/restore).

Consequências práticas:

- `supabase db push --local` → **não funciona** (conflito de PK de version nos pares).
- Reset fresh (`supabase start` com a pasta de migrations cheia) → **não funciona** (0096).
- **Self-host VPS e CI** (install.sh/update.sh, `test:db`, e2e) → aplicam **baseline.sql** —
  não são afetados. É a doutrina do `AGENTS.md`.

Fluxo correto, em uma frase: **baseline + restore para nascer; migrations (manuais) só
para evoluir.**

---

## 2. DR — snapshot completo (dump)

Regra de ouro: **antes de qualquer ajuste no banco main, criar o dump**.

Usar `supabase_admin` (superuser). `postgres` NÃO é superuser no Supabase local —
restore com ele gera ~985 erros de owner/grants/event-trigger.

```cmd
:: main (container supabase_db_deskcomm-crm)
docker exec supabase_db_deskcomm-crm pg_dump -U supabase_admin -Fc -d postgres -f /tmp/dr-main-YYYY-MM-DD.dump
docker cp supabase_db_deskcomm-crm:/tmp/dr-main-YYYY-MM-DD.dump backups\deskcomm-main-YYYY-MM-DD.dump
docker exec supabase_db_deskcomm-crm rm /tmp/dr-main-YYYY-MM-DD.dump
```

:: dev (container supabase_db_deskcomm-crm-dev) — idem, prefixo `deskcomm-dev-`.

---

## 3. Restore

```cmd
docker exec -i supabase_db_deskcomm-crm pg_restore -U supabase_admin -d postgres --clean --if-exists < backups\deskcomm-main-YYYY-MM-DD.dump
```

- **`-U supabase_admin` obrigatório** (0 erros esperados).
- **Não usar `--no-owner`**: owners/grants/event-triggers precisam ser restaurados com
  superuser; `--no-owner` perde fidelidade de owners.
- `restore-snapshot.cmd` (rollback para o snapshot de 03/08) é **específico daquele
  snapshot**: a lista de drops manuais do passo 3 reflete as migrations 0088–0098 daquela
  data. Ao criar um snapshot novo, **revisar essa lista** — ex.: `trg_seed_org_llm_defaults`
  agora EXISTE no banco (0096 do upstream aplicado em 05/08) e não deve ser dropado num
  rollback para um snapshot posterior a 05/08.

---

## 4. Aplicar uma migration nova (fluxo manual — o único suportado)

Migrations do fork são idempotentes (`add column if not exists`, `drop ... if exists`,
guards em `do $$`). Aplicação:

```cmd
:: 1. SQL no banco
type supabase\migrations\<arquivo>.sql | docker exec -i supabase_db_deskcomm-crm psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1

:: 2. Registrar em schema_migrations (statements '{}' = aplicada fora do CLI)
docker exec supabase_db_deskcomm-crm psql -U supabase_admin -d postgres -c "insert into supabase_migrations.schema_migrations (version, name, statements) values ('<timestamp>', '<sufixo_do_arquivo>', '{}') on conflict (version) do update set name = excluded.name"

:: 3. PostgREST recarrega o schema
docker exec supabase_db_deskcomm-crm psql -U supabase_admin -d postgres -c "notify pgrst, 'reload schema'"
```

Repetir no dev (`supabase_db_deskcomm-crm-dev`) com o mesmo arquivo. Dev e main devem
ficar **idênticos** em `schema_migrations` (hoje: 92 linhas, iguais).

> Caso especial 0096: o registro `20260730200000` guardava o **nome antigo** do arquivo do
> fork (pré-rename de fcbec23) e a migration do upstream (`0096_llm_default_model_da_org`)
> nunca tinha sido aplicada — o CLI a tratava como aplicada. Corrigido em 05/08:
> migration aplicada nas duas stacks + nome do registro atualizado.

---

## 5. Histórico de snapshots

| Data | Arquivo | Observação |
|---|---|---|
| 2026-08-03 | `deskcomm-supabase-pre-migracao-2026-08-03.dump` | Antes do merge/0098; alvo do `restore-snapshot.cmd` |
| 2026-08-04 | `deskcomm-main-2026-08-04.dump` | DR antes da aplicação de 0098/0099 |
| 2026-08-05 | `deskcomm-main-2026-08-05.dump` | DR antes da aplicação de 0096_llm_default_model |

---

## 6. Colisões de timestamp fork × upstream — política (definida 2026-08-05)

Colisões com o upstream serão **constantes** (projetos independentes — o fork tem
mudanças próprias que colidem com as deles). Procedimento quando um merge do
upstream trouxer arquivo com **timestamp igual** ao de um arquivo do fork:

1. **Comparar o conteúdo** dos dois arquivos (`git diff`).
2. **Iguais** → manter, sem ação.
3. **Diferentes** → **renomear o arquivo DO FORK** para um timestamp novo e único
   (ex.: `fcbec23` renomeou o `0096_recreate_organizations` de `20260730200000` →
   `20260428195500`). Nunca sobrescrever o do upstream.

> Os 4 pares atuais (0034/0038, 0042/0043, 0054/0055, 0062/0064) são **internos do
> upstream** — os 8 arquivos vieram de commits deles, não há arquivo do fork no par.
> Ficam como estão (conteúdo já no schema via baseline; fluxo manual de aplicação);
> a correção dos timestamps é responsabilidade do upstream.
