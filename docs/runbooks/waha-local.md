---
title: Runbook — WAHA em desenvolvimento local (Docker Desktop / Windows)
status: canônico
last_review: 2026-07-30
owner: DevOps
---

# Runbook — WAHA em desenvolvimento local

> Guia de setup do WAHA (WhatsApp HTTP API) com engine NOWEB para desenvolvimento
> local no Windows com Docker Desktop. Documenta as armadilhas já resolvidas para
> que a migração para produção (VPS) ocorra sem repetir os mesmos erros.

---

## 1. Stack

| Componente | Versão / Imagem | Porta |
|---|---|---|
| WAHA | `devlikeapro/waha:noweb` (imagem NOWEB) | 3030 → 3000 (container) |
| Redis | — | — |
| CRM (Next.js) | `npm run dev` | 3000 |
| Supabase | Local CLI (127.0.0.1:54321) | 54321 |
| Worker | `Dockerfile.worker` | 8787 |

> A engine **NOWEB** é obrigatória — a engine WEBJS (default do WAHA) depende de
> Puppeteer/Chromium e consome ~500MB+ por sessão. NOWEB usa Baileys (WebSocket)
> direto, ~150MB por sessão e não precisa de sandbox de navegador.

---

## 2. Arquivos de configuração

### 2.1 `docker-compose.yml`

```yaml
services:
  waha:
    image: devlikeapro/waha:noweb           # NÃO use devlikeapro/waha (sem tag)
    platform: linux/amd64                    # necessário no ARM Macs se for o caso
    container_name: deskcomm-waha
    restart: unless-stopped
    ports:
      - "3030:3000"                          # host 3030 → container 3000
    environment:
      # ⚠️ SHA512 HASH da API key, NÃO o plaintext!
      # Gere: echo -n "$WAHA_API_KEY" | sha512sum | awk '{print $1}'
      WAHA_API_KEY: ${WAHA_API_KEY_SHA512}
      WHATSAPP_HOOK_URL: ${WAHA_HOOK_BASE_URL}/api/v1/webhooks/waha
      WHATSAPP_HOOK_EVENTS: "message,message.any,message.ack,session.status,state.change"
      WHATSAPP_HOOK_HMAC: ${WAHA_HMAC_SECRET}
      WHATSAPP_DEFAULT_ENGINE: NOWEB         # essencial — WAHA usa env WRONG
      WAHA_DASHBOARD_ENABLED: "true"         # false em produção
    extra_hosts:
      - "host.docker.internal:host-gateway"  # webhooks → host: next dev
    volumes:
      - waha-data:/app/.sessions
      - waha-media:/app/.media
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:3000/ping"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
```

### 2.2 `.env.local` (variáveis de ambiente)

```bash
# --- WAHA ---
WAHA_API_KEY=mIgoSUd3sz8y5Qlb0pqCHcPMK2JnTu6R
WAHA_API_KEY_SHA512=<hash da chave acima>
WAHA_HMAC_SECRET=5cffcc4083a57afb4783a3589d673068df5952711c623eedca3a3f1bb9fc83a6
WAHA_DASHBOARD_USERNAME=admin
WAHA_DASHBOARD_PASSWORD=deskcomm-waha-local-2026
WAHA_HOOK_BASE_URL=http://host.docker.internal:3000
WAHA_API_BASE_URL=http://127.0.0.1:3030
WAHA_DEFAULT_ENGINE=NOWEB
WAHA_DASHBOARD_ENABLED=true
```

---

## 3. Comandos essenciais

```bash
# Subir WAHA (sempre com --env-file .env.local!)
docker compose --env-file .env.local up -d waha

# Ver logs
docker compose --env-file .env.local logs -f waha

# Parar
docker compose --env-file .env.local down waha

# Testar conectividade
curl -s -H "X-Api-Key: mIgoSUd3sz8y5Qlb0pqCHcPMK2JnTu6R" http://127.0.0.1:3030/api/sessions
```

> ⚠️ **Sempre use `--env-file .env.local`** — `docker compose` sem o flag lê
> apenas `.env` (que está vazio / tem só comentários) e o WAHA sobe sem as
> variáveis obrigatórias.

---

## 4. Problemas resolvidos (lições aprendidas)

### 4.1 🔴 WAHA Connection Failure no Baileys

**Sintoma:** WAHA log mostra loop infinito:
```
connected to WA → attempting registration → connection errored (Error: Connection Failure) → reconnect (2s)
```

**Causa:** A imagem `devlikeapro/waha:noweb` estava desatualizada localmente.
O erro `Connection Failure` ocorre no handshake de noise do Baileys
(`Object.decodeFrame` em `socket.js:806`) — uma incompatibilidade de protocolo
entre o cliente Baileys embutido na imagem e os servidores do WhatsApp Web.

**Fix:** `docker compose pull waha` para forçar o download da imagem mais
recente, depois `docker compose up -d waha`.

```bash
docker compose --env-file .env.local pull waha
docker compose --env-file .env.local up -d waha
```

**Verificação:** WAHA deve logar "QR code generated" e exibir o QR.

### 4.2 🔴 docker compose perde variáveis de ambiente

**Sintoma:** WAHA inicia mas dashboard retorna 401 para qualquer requisição,
ou retorna "WAHA is not connected".

**Causa:** `docker compose up -d waha` (sem `--env-file .env.local`) lê apenas
`.env`, que está vazio. O container WAHA roda sem `WAHA_API_KEY`,
`WHATSAPP_HOOK_URL`, etc.

**Fix:** Sempre usar `--env-file .env.local`:

```bash
docker compose --env-file .env.local up -d waha
docker compose --env-file .env.local down waha
docker compose --env-file .env.local logs -f waha
```

**Verificação:** `docker exec deskcomm-waha env | grep WAHA` para confirmar
que as variáveis estão presentes.

### 4.3 🔴 WAHA_API_KEY: SHA512 hash vs plaintext

**Sintoma:** WAHA rejeita chamadas da API (`401 Unauthorized`).

**Causa:** O WAHA Plus espera a chave em formato **SHA512 hash** na env var
`WAHA_API_KEY` (dentro do container), mas o cliente envia a chave em plaintext
no header `X-Api-Key`. O WAHA hasheia o plaintext recebido e compara com o
hash armazenado.

**Fix:** A env var `WAHA_API_KEY` no `docker-compose.yml` deve conter o SHA512
hash, NÃO o plaintext. Gerar:

```bash
echo -n "mIgoSUd3sz8y5Qlb0pqCHcPMK2JnTu6R" | sha512sum | awk '{print $1}'
```

**Nota:** No ambiente de desenvolvimento local, o `.env.local` contém tanto o
plaintext (`WAHA_API_KEY`) quanto o hash (`WAHA_API_KEY_SHA512`). O
`docker-compose.yml` referencia `${WAHA_API_KEY_SHA512}` na env var do
container.

### 4.4 🟡 Sessions órfãs no WAHA

**Sintoma:** Ao reconectar, aparece "session already exists" ou QR não aparece.

**Causa:** Sessions de teste anteriores que não foram limpas.

**Fix:** Parar e deletar via API ou pelo botão "Desconectar" no CRM.

```bash
curl -X DELETE -H "X-Api-Key: <key>" http://localhost:3030/api/sessions/<session_name>
```

### 4.5 🟡 WHATSAPP_DEFAULT_ENGINE vs WAHA_DEFAULT_ENGINE

**Sintoma:** WAHA usa engine WEBJS (navegador) mesmo com
`WAHA_DEFAULT_ENGINE=NOWEB` configurado.

**Causa:** O WAHA **não** lê `WAHA_DEFAULT_ENGINE` — o nome correto da env var
é `WHATSAPP_DEFAULT_ENGINE`. A nomenclatura WAHA_* para engine foi usada em
versões antigas e caiu silenciosamente no default WEBJS.

**Fix:** Usar `WHATSAPP_DEFAULT_ENGINE: NOWEB` no docker-compose.yml.

### 4.6 🟡 Webhook não chega ao CRM em dev

**Sintoma:** Mensagens enviadas pelo WhatsApp não aparecem no CRM.

**Causa:** Dentro do container, `localhost` é o próprio WAHA — o webhook precisa
apontar para o **host** onde o Next.js dev server roda.

**Fix:** Usar `host.docker.internal` no `WAHA_HOOK_BASE_URL`, que resolve para
o IP da máquina host Windows/Mac a partir do container Docker:

```bash
WAHA_HOOK_BASE_URL=http://host.docker.internal:3000
```

E no docker-compose.yml:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

---

## 5. Dashboard WAHA

Em desenvolvimento, o dashboard está habilitado em:

- **URL:** http://localhost:3030/dashboard
- **Login:** `admin`
- **Senha:** `deskcomm-waha-local-2026`

Útil para depuração visual (ver sessions, testar QR, enviar mensagens de teste).

> **Em produção, desabilitar:** `WAHA_DASHBOARD_ENABLED: "false"`.

---

## 6. Fluxo de conexão WhatsApp

```
Usuário clica "Conectar novo WhatsApp"
  → POST /api/v1/channel-sessions
    → Cria registro em channel_sessions (status=STARTING)
    → POST /api/sessions (WAHA) → nome: org_{orgId[:8]}_{randomUUID[:6]}
    → POST /api/sessions/{name}/start (WAHA)
    → Retorna 201 com o registro

Frontend abre QrDialog
  → Polling GET /api/v1/channel-sessions/{id} a cada 3s
  → Quando status=SCAN_QR_CODE, exibe <img src="/api/v1/channel-sessions/{id}/qr">
  → Quando status=WORKING, fecha dialog e mostra "Conectado!"

Usuário escaneia QR com celular
  → WAHA muda status para WORKING
  → Polling detecta WORKING → onConnected()
```

---

## 7. API de Desconexão

Nova funcionalidade implementada em 2026-07-30:

**DELETE /api/v1/channel-sessions/[id]**

1. Para a sessão no WAHA (POST /api/sessions/{name}/stop)
2. Deleta a sessão no WAHA (DELETE /api/sessions/{name})
3. Remove o registro do Supabase (channel_sessions)
4. Audita ação (`channel.disconnected`)

Ações do admin disponível na UI em `ConnectionsClient.tsx` — botão "Desconectar"
com confirmação (`window.confirm`).

---

## 8. Para migrar para VPS

Durante a migração para o VPS (Hostgator), atente-se aos itens que já causaram
problemas em dev:

- [ ] **Sempre** usar `WHATSAPP_DEFAULT_ENGINE: NOWEB` (a env `WAHA_DEFAULT_ENGINE`
      não funciona)
- [ ] A env `WAHA_API_KEY` no container deve conter o **SHA512 hash** da chave,
      não o plaintext (com exceção do WAHA Plus que aceita plaintext direto —
      verificar qual build está em uso)
- [ ] **Não usar `:latest`** — pinar digest SHA256 (ver runbook `waha-hostgator.md`)
- [ ] Webhook URL público (ex: `https://app.deskcomm.com.br/api/v1/webhooks/waha`)
- [ ] Nginx com `proxy_buffering off` (SSE do WAHA)
- [ ] Dashboard **desabilitado** em produção
- [ ] Backup do volume `waha-data` (contém `.sessions` com dados de pareamento)
- [ ] `extra_hosts` e `host.docker.internal` não existem em Linux — webhooks vão
      direto pelo IP da bridge Docker ou domínio público
