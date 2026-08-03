# Operações — DeskcommCRM

> Guia de operação, persistência, backup e migração entre ambientes.
> **Repositório do projeto:** `vagnercoach` (privado no GitHub)

---

## 1. Persistência de Dados

### 1.1 Bind mounts (disco físico)

Desde 2026-07-30, todos os dados persistentes usam **bind mounts** no disco físico (não volumes nomeados Docker). Os caminhos são **relativos** (`./data/...`) — funcionam igual em Windows (Docker Desktop) e Linux (VPS).

| Serviço | Bind mount | Conteúdo |
|---------|-----------|----------|
| WAHA sessions | `./data/waha/sessions/` → `/app/.sessions` | Estado de pareamento WhatsApp (~47k arquivos, ~50MB). **Crown jewel** — perdê-lo força re-scan de QR. |
| WAHA media | `./data/waha/media/` → `/app/.media` | Cache de mídia inbound (vazio no momento). |
| Redis | `./data/redis/` → `/data` | Cache de rate-limit, contadores, filas. AOF ligado (`appendfsync everysec`). |

> **Atenção:** esses diretórios NÃO são versionados no git (`.gitignore` contém `data/` e `data/backups/`).

### 1.2 Supabase (local)

O Supabase CLI local (`supabase start`) gerencia seu próprio volume Docker nomeado (`supabase_db_deskcomm-crm`). **Não é bind mount.** Para preservar dados antes de reset:

```bash
# Antes de qualquer supabase stop / db reset:
supabase db dump -f supabase/backups/pre-reset-$(date +%Y-%m-%d).sql
```

---

## 2. Backup Diário

Script: `scripts/backup.ps1` (PowerShell) / `scripts/backup.bat` (wrapper para Task Scheduler).

### O que o backup inclui

1. **Supabase** — `pg_dump --format=custom --compress=9` via docker exec
2. **WAHA sessions** — tar.gz via `--volumes-from` com `docker pause` (consistente)
3. **WAHA media** — tar.gz via `--volumes-from`
4. **Redis** — `redis-cli SAVE` + tar.gz via docker exec

### Destino

`./data/backups/YYYY-MM-DD/` — um diretório por dia, com retenção de 7 dias (configurável via `-KeepDays`).

### Agendamento

**2x/dia — 06:00 e 19:00** (configurado em 2026-07-30).

#### Windows (Task Scheduler)

```cmd
schtasks /CREATE /SC DAILY /TN "DeskcommCRM-Backup-06h" /TR "D:\qwenProjects\deskcommcrm\scripts\backup.bat" /ST 06:00
schtasks /CREATE /SC DAILY /TN "DeskcommCRM-Backup-19h" /TR "D:\qwenProjects\deskcommcrm\scripts\backup.bat" /ST 19:00
```

Ou via Agendador de Tarefas: criar **duas** tarefas básicas → diária → 06:00 e 19:00 → iniciar programa → `scripts\backup.bat`.

> **Importante:** `backup.bat` executa PowerShell com `ExecutionPolicy Bypass`. O usuário que executa o agendamento precisa de permissão de leitura/escrita em `./data/backups/`.

#### Linux (cron)

```bash
# Editar crontab:
crontab -e

# Adicionar:
0 6 * * * /opt/deskcommcrm/scripts/backup.sh
0 19 * * * /opt/deskcommcrm/scripts/backup.sh
```

O script `scripts/backup.sh` é o equivalente shell multiplataforma do `backup.ps1`. Idêntica lógica: pg_dump + docker pause/volumes-from para WAHA + redis-cli SAVE + limpeza.

### Restauração

```bash
# Supabase:
pg_restore --format=custom --dbname=postgresql://... supabase_<data>.dump

# WAHA sessions:
tar xzf waha-sessions_<data>.tar.gz -C ./data/waha/sessions/

# Redis:
# docker stop deskcomm-redis; substituir dump.rdb + appendonly.aof; docker start
```

---

## 3. Migração para VPS (Linux)

### 3.1 O que muda

| Item | Windows (dev) | VPS (Linux) | Impacto |
|------|--------------|-------------|---------|
| Caminhos bind mount | `./data/...` | `./data/...` | **Nada muda** — caminhos relativos funcionam em ambos |
| Docker Compose | `docker compose --env-file .env.local up -d` | `docker compose --env-file .env.prod up -d` | Apenas o arquivo de env |
| Supabase | CLI local (volume nomeado) | Supabase Cloud (managed) | **Não usar Supabase CLI na VPS** — conectar ao Cloud via `SUPABASE_DB_URL` |
| WAHA URL | `http://localhost:3030` | URL pública com TLS | Atualizar `WAHA_API_BASE_URL` no env |
| Backup | script PowerShell | script shell (`backup.sh`) | Converter a lógica |

### 3.2 Passos para deploy na VPS

1. **Clone o repo** no servidor:
   ```bash
   git clone git@github.com:vagnercoach/deskcommcrm.git /opt/deskcommcrm
   ```

2. **Crie os diretórios de dados:**
   ```bash
   mkdir -p /opt/deskcommcrm/data/waha/{sessions,media}
   mkdir -p /opt/deskcommcrm/data/redis
   mkdir -p /opt/deskcommcrm/data/backups
   ```

3. **Configure o `.env.prod`** no servidor (copiar do `hostgator.example`):
   ```bash
   cp .env.hostgator.example .env.prod
   # Editar com credenciais reais
   ```

4. **Copie os dados da sessão WAHA** (se migrando de dev):
   ```bash
   # No Windows, transferir via SCP/rsync o diretório:
   scp -r ./data/waha/sessions/* user@vps:/opt/deskcommcrm/data/waha/sessions/
   ```

5. **Suba os containers:**
   ```bash
   cd /opt/deskcommcrm
   docker compose --env-file .env.prod up -d
   ```

6. **Configure o backup** no crontab (2x/dia):
   ```bash
   # O script backup.sh já está no repositório
   0 6 * * * /opt/deskcommcrm/scripts/backup.sh
   0 19 * * * /opt/deskcommcrm/scripts/backup.sh
   ```

### 3.3 Supabase: local → Cloud

Na VPS, não usar Supabase CLI. Conectar diretamente ao Supabase Cloud via:

```env
# .env.prod
NEXT_PUBLIC_SUPABASE_URL=https://seu-projeto.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
SUPABASE_DB_URL=postgresql://postgres:password@aws-0-sa-east-1.pooler.supabase.com:6543/postgres
```

Para migrar dados do local para o Cloud:
```bash
# 1. Dump do local (já feito pelo backup diário)
# 2. Restaurar no Supabase Cloud:
psql "$SUPABASE_DB_URL" < dump.sql

# Ou via pg_restore:
pg_restore --format=custom --dbname="$SUPABASE_DB_URL" supabase_<data>.dump
```

---

## 5. Rollback

A política completa de rollback e migrações está em [`migration-policy.md`](./migration-policy.md).

**Comandos rápidos:**

```bash
# Restaurar DB do backup mais recente
./scripts/rollback.sh --db

# Reverter compose ao commit anterior + restart
./scripts/rollback.sh --app

# Rollback completo (DB + app)
./scripts/rollback.sh --full --date 2026-07-30
```

**Windows:**
```cmd
scripts\rollback.bat db
scripts\rollback.bat app
scripts\rollback.bat full 2026-07-30
```

---

## 6. Arquivos Alterados/Adicionados

| Arquivo | O que mudou |
|---------|------------|
| `docker-compose.yml` | WAHA: volumes nomeados → bind mounts (`./data/waha/...`) |
| `docker-compose.override.yml` | Redis: adicionado bind mount + AOF ativado |
| `docker-compose.prod.yml` | WAHA: volumes nomeados → bind mounts (mesmo padrão do dev) |
| `.gitignore` | Adicionado `data/` e `data/backups/` |
| `scripts/backup.ps1` | **Novo** — backup diário completo (PowerShell) |
| `scripts/backup.sh` | **Novo** — backup diário completo (shell, Linux/VPS) |
| `scripts/backup.bat` | **Novo** — wrapper para Task Scheduler |
| `scripts/rollback.sh` | **Novo** — rollback DB + app (shell, Linux/VPS) |
| `scripts/rollback.bat` | **Novo** — wrapper rollback para Windows |
| `supabase/migrations/20260428195500_0096_recreate_organizations.sql` | **Novo** — recria organizations (migration 0001 era stub) |
| `supabase/migrations/down/20260428195500_0096_recreate_organizations.down.sql` | **Novo** — reversão da migration 0096 (em `down/` para o CLI não aplicá-la) |
| `docs/operations/migration-policy.md` | **Novo** — política de migrações, rollback e fork safety |

### WAHA sessions agora em disco

Antes (`docker-compose.yml`):
```yaml
volumes:
  - waha-data:/app/.sessions     # volume nomeado (WSL2)
```

Depois:
```yaml
volumes:
  - type: bind
    source: ./data/waha/sessions  # disco físico
    target: /app/.sessions
```

O volume nomeado antigo `deskcommcrm_waha-data` ainda existe no Docker (dados preservados), mas não é mais usado. Pode ser removido após confirmação:

```bash
docker volume rm deskcommcrm_waha-data
```
