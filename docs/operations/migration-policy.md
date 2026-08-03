# Política de Migrações — DeskcommCRM

> Como escrever, revisar e reverter migrações de banco de dados de forma segura.
> Estabelecido em 2026-07-30 após incidente de perda de dados (migration 0001 era stub).

---

## 1. Toda migration DEVE ter um down

Cada migration `NNNNNNNNNNNN_desc.sql` DEVE ter um arquivo `NNNNNNNNNNNN_desc.down.sql` correspondente que a reverte completamente.

**Estrutura:**
```
supabase/migrations/
├── 20260428195354_0001_platform_base.sql                  # stub original (sem down)
├── 20260428195500_0096_recreate_organizations.sql
└── down/
    └── 20260428195500_0096_recreate_organizations.down.sql   # <── reversão
```

**Por que em `down/`:** o Supabase CLI aplica todo arquivo que casa com `<timestamp>_name.sql` na raiz de `supabase/migrations/` — o regex do CLI (`^([0-9]+)_(.*)\.sql$`) aceita pontos, então um `.down.sql` na raiz seria executado como migration normal num `db push`/`migration up` acidental. O CLI ignora subdiretórios (`migration.IsDir() → continue`), então `down/` blinda a reversão de aplicação acidental.

**O down DEVE:**
1. Remover dados inseridos pela migration (`DELETE`)
2. Remover objetos criados (tabelas, funções, triggers)
3. Manter `fn_touch_updated_at()` se for compartilhada por outras tabelas

**Exceções:** Migrations que criam extensões (`CREATE EXTENSION`) não têm down (remover extensão quebra outras tabelas que a usam).

---

## 2. Regras anti-destrutivas

### 2.1 Backup ANTES de migration

Sempre executar o backup antes de aplicar migrations destrutivas:

```bash
# Antes de migration com DROP / ALTER COLUMN type / DELETE em massa
./scripts/backup.sh

# Verificar se o dump foi criado:
ls -la data/backups/$(date +%Y-%m-%d)/
```

### 2.2 Migrations destrutivas REQUEREM aprovação

Uma migration é considerada **destrutiva** se:

- `DROP TABLE` ou `DROP COLUMN`
- `ALTER COLUMN ... TYPE` (muda tipo de coluna com dados)
- `DELETE` ou `TRUNCATE` em massa
- Renomear tabelas/colunas que podem ter referências externas

Para estas, o fluxo é:

```
1. Criar migration + down correspondente
2. Executar backup manual
3. Aplicar migration (supabase db up)
4. Validar dados
5. Só então remover o down migration (se aplicável)
```

### 2.3 Preferir additive migrations

Sempre que possível, prefira:

✅ `ADD COLUMN ... DEFAULT` (aditivo, não quebra)
✅ `CREATE TABLE` (novo, não impacta existente)
✅ `CREATE INDEX CONCURRENTLY` (sem lock)
✅ `ALTER TABLE ... ADD CONSTRAINT ... NOT VALID` (valida depois)

❌ `DROP COLUMN` (perda de dados)
❌ `ALTER COLUMN ... TYPE` (pode truncar dados)
❌ `DROP TABLE ... CASCADE` (arrasta FKs)

### 2.4 Versionamento

Todas as migrations são versionadas no git. **Nunca** editar uma migration já aplicada — criar uma nova.

---

## 3. Rollback

### 3.1 DB Rollback via backup (recomendado)

Usar o backup diário para restaurar o estado completo do banco:

```bash
# Restaurar do backup mais recente
./scripts/rollback.sh --db

# Restaurar de uma data específica
./scripts/rollback.sh --db --date 2026-07-30
```

O script:
1. Encontra o dump mais recente em `./data/backups/YYYY-MM-DD/`
2. Valida a integridade (`pg_restore --list`)
3. Para serviços que acessam o DB (worker, srh)
4. Executa `pg_restore --clean --if-exists`

### 3.2 DB Rollback via down migration

Usar apenas para reverter a ÚLTIMA migration (dados mais recentes podem ser perdidos):

```bash
docker exec -i supabase_db_deskcomm-crm psql -U postgres -d postgres \
  < supabase/migrations/down/20260428195500_0096_recreate_organizations.down.sql
```

> ⚠ **Atenção:** down migration não restaura dados excluídos por outras migrations.
> Prefira o rollback via backup (seção 3.1) sempre que possível.

### 3.3 App Rollback (Docker Compose)

Reverter os arquivos `docker-compose.*.yml` ao commit anterior + restart:

```bash
./scripts/rollback.sh --app
```

**Windows:**
```cmd
scripts\rollback.bat app
```

---

## 4. Fluxo de atualização segura

```
1. git pull (ou merge de branch)
2. docker compose pull         # atualizar imagens
3. ./scripts/backup.sh         # backup ANTES da migration
4. docker compose up -d        # sobe containers com código novo
   # ── Se houver migrations ──
5. supabase db up              # aplicar migrations (local)
   # ── Validar ──
6. Verificar health checks:
   docker compose ps
   curl http://localhost:3000/api/v1/health
7. Se algo quebrar:
   ./scripts/rollback.sh --full --date YYYY-MM-DD
```

---

## 5. Git: Fork safety

O repositório é um fork de `melgarafael/DeskcommCRM`. Arquivos modificados localmente:

| Arquivo | Risco de conflito | Como mitigar |
|---------|------------------|--------------|
| `docker-compose.yml` | **ALTO** | Manter diff mínimo; bind mounts são retrocompatíveis |
| `docker-compose.prod.yml` | **ALTO** | Mesmo que acima |
| `docker-compose.override.yml` | **ALTO** | Não versionar upstream (`.gitignore` ou manter separado) |
| `.gitignore` | Baixo | Merges automáticos geralmente funcionam |
| `supabase/migrations/` | **MÉDIO** | Migrations são sequenciais por timestamp; conflito só se timestamps colidirem |

**Estratégia recomendada:**

```bash
# Ao puxar upstream:
git remote add upstream git@github.com:melgarafael/DeskcommCRM.git
git fetch upstream

# Rebasear mudanças locais sobre upstream:
git checkout main
git pull upstream main --rebase
# Resolver conflitos nos composes se necessário
```

> ⚠ Os diretórios `data/`, `data/backups/` e `docs/operations/` são **exclusivos do fork** (`vagnercoach`). Não existem no upstream. Merges do upstream não afetam dados.
