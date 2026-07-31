---
name: Sistema de convite e criação de tenants
description: Implementação completa do fluxo invite-only (requisitos 02-05) — signup apenas por convite, admin cria org + invite do owner
type: project
---

## Itens implementados (2026-07-30)

### Requisito 02 — Invite-only (sem autosserviço)
- Signup sem `?invite=` param mostra mensagem "Cadastro por convite"
- Signup com `?invite=<token>&email=<email>` mostra formulário simplificado (email fixo + senha)
- `signUp.ts` armazena `invite_redirect` em `user_metadata`
- `/auth/confirm` detecta `invite_redirect`, pula `ensureTenantForUser` (skipProvision), redireciona para página de aceite
- `ensureTenantForUser` aceita `{ skipProvision?: boolean }` opcional

### Requisito 03 — Admin cria empresas (conectado)
- `POST /api/v1/admin/tenants` agora gera invite HMAC para `owner_email` após criar org
- Response inclui `invite: { email, invite_url, expires_at }`
- Admin form (`/admin/tenants/new`) exibe o link de convite após criação, com botão copiar

### Requisito 04 — Admin designa admin da empresa
- Owner invite é gerado com `role: "admin"` — ao aceitar, vira admin da org

### Requisito 05 — Company admin gerencia usuários
- Já funcionava via `/app/team/invite` (invite com HMAC + fallback Resend mostrando link) + `/app/team` (gerenciamento)

### Fluxo completo de signup via convite
1. Platform admin cria org → link de invite gerado
2. Owner visita link → `/team/accept-invite/{token}`
3. Se não logado: vê "Criar conta com {email}" + "Fazer login"
4. "Criar conta" → `/signup?invite={token}&email={email}`
5. Formulário com email fixo + senha → cria auth user + `invite_redirect`
6. Confirma email → `/auth/confirm` → detecta `invite_redirect` → pula provisionamento → redireciona para aceite
7. Owner autenticado clica "Aceitar convite" → `acceptInviteAction` cria membership `admin`

### Arquivos modificados
- `lib/auth/schemas.ts` — org_name opcional, invite_token adicionado
- `app/actions/auth/signUp.ts` — suporte a invite_token, invite_redirect em metadata
- `lib/auth/provision.ts` — skipProvision option
- `app/auth/confirm/route.ts` — redirect para invite_redirect
- `components/auth/SignupForm.tsx` — props invite/email, formulário adaptável
- `app/(public)/signup/page.tsx` — searchParams para form
- `app/team/accept-invite/[token]/page.tsx` — "Criar conta" para não autenticados
- `app/api/v1/admin/tenants/route.ts` — geração de invite HMAC para owner
- `hooks/useCreateTenant.ts` — tipo de resposta com invite
- `app/admin/(protected)/tenants/new/_form.tsx` — card de resultado com link de convite

### Testes
- Typecheck: 0 errors
- Test suite: **1448 passed, 2 pre-existing failures** (0 new)
