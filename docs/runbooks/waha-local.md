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
      # ⚠️ Build noweb: plaintext DIRETO — o container compara o header
      # X-Api-Key contra WAHA_API_KEY sem hash. NÃO use o SHA512 aqui.
      # (O docker-compose.override.yml limpa WAHA_API_KEY_SHA512 por segurança.)
      WAHA_API_KEY: ${WAHA_API_KEY}
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

### 4.3 🟢 WAHA_API_KEY: plaintext direto (build noweb), NÃO SHA512

> Atualizado em 2026-08-14. O comportamento anterior (SHA512 hash) era do
> build **WAHA Plus**; o build deste projeto é `devlikeapro/waha:noweb`.

**Sintoma que esse item previne:** WAHA rejeita chamadas da API (`401
Unauthorized`) porque o container recebeu o SHA512 hash em `WAHA_API_KEY`, mas o
cliente manda o plaintext no header `X-Api-Key` — e o noweb compara os dois
**diretamente**, sem hashear.

**Como o noweb autentica:** o container compara o header `X-Api-Key` recebido
**diretamente** contra o valor de `WAHA_API_KEY` (plaintext). Não há hashing.
Portanto `WAHA_API_KEY` (em `.env` / `.env.local` e no env do container) é o
plaintext, e o `docker-compose.override.yml` **limpa** `WAHA_API_KEY_SHA512`
(`WAHA_API_KEY_SHA512: ""`) para não deixar dúvida.

**Fix se der 401:** garanta que o container subiu com o plaintext:
```bash
docker exec deskcomm-waha env | grep WAHA_API_KEY
# esperado: WAHA_API_KEY=mIgoSUd3sz8y5Qlb0pqCHcPMK2JnTu6R (sem hash, sem SHA512)
```
Se aparecer um hash longo, o override não foi aplicado ou o `.env` traz o hash
— subir com `--env-file .env.local` e confirmar o override mesclado.

**Atenção ao trocar de build:** o **WAHA Plus** É que usa SHA512 hash (o
container tem o hash e hasheia o plaintext do header para comparar). Se um dia
trocar `image:` para `waha-plus`, aí `WAHA_API_KEY` no container vira o hash —
não o plaintext. Mantenha o `.env.local` com ambos (`WAHA_API_KEY` plaintext +
`WAHA_API_KEY_SHA512`) para essa eventualidade, mas saiba que no noweb só o
plaintext é usado.

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
- [ ] A env `WAHA_API_KEY` no container é o **plaintext** neste build
      (`devlikeapro/waha:noweb`, que compara o `X-Api-Key` direto). Só vira
      **SHA512 hash** se trocar o image para `waha-plus` — confirmar qual build
      está em uso na VPS antes de copiar o `.env`.
- [ ] **Não usar `:latest`** — pinar digest SHA256 (ver runbook `waha-hostgator.md`)
- [ ] **Não sugerir ngrok** — VPS já tem HTTPS; webhooks resolvem via rede interna Docker. Não usar EasyPanel.
- [ ] Nginx com `proxy_buffering off` (SSE do WAHA)
- [ ] Dashboard **desabilitado** em produção
- [ ] Backup do volume `waha-data` (contém `.sessions` com dados de pareamento)
- [ ] `extra_hosts` e `host.docker.internal` não existem em Linux — webhooks vão
      direto pelo IP da bridge Docker ou domínio público

---

## 9. Política de sessão — o dev NUNCA conecta o número real (2026-08-05)

### Por quê

O WhatsApp mantém **uma única conexão ativa por número** e uma fila de entrega
no servidor: quando o número fica offline, as mensagens ficam retidas e são
entregues assim que ele reconecta. Conectar o número real em **qualquer** outra
instância (ex.: o WAHA dev) tem dois efeitos:

1. A sessão anterior (prod) é derrubada no WhatsApp;
2. A fila de mensagens retidas é **drenada para a conexão nova** (o dev).

Resultado: o banco de produção nunca recebe as mensagens que chegaram durante o
período de teste — para o prod, é perda. O modelo "prod dormente durante testes"
só funciona se o número real ficar **offline** no período; aí a fila entrega tudo
ao prod quando ele voltar.

### Regras

- **Nunca** escanear o QR do número real no WAHA dev (dashboard 3030).
- As sessões do dev vivem em `./data/waha/sessions-dev` (bind separado desde
  2026-08-05). O WAHA dev não enxerga `./data/waha/sessions` (reservada ao prod
  local/VPS) e não auto-conecta sessão nenhuma.
- Testar o pipeline de mensagens com **webhook simulado** (abaixo) ou com um
  número de teste dedicado, se um dia existir.

### Simular um webhook de mensagem (sem WhatsApp real)

App dev no ar (porta do app em `.env.local` → `NEXT_PUBLIC_APP_URL`; padrão 3000) e
uma sessão de teste registrada em `channel_sessions`:

```bash
pnpm simulate:waha
# personalizar:
pnpm simulate:waha --session <waha_session_name> --text "Oi! Vi o anúncio" --from 5531999990001
```

`scripts/simulate-waha-message.ts` posta um inbound de texto no endpoint
per-tenant e prova que a mensagem foi gravada em `messages`. Só cobre a
**ingestão**; para provocar um turno real do agente (exige credencial LLM e
worker rodando), usar `scripts/provoke-agent-turn.ts`.
