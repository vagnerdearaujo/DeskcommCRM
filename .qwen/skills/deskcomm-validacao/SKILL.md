---
name: deskcomm-validacao
description: Valida o DeskComm de ponta a ponta — typecheck, lint, testes unitários e E2E operando o browser (Chrome/Edge via Playwright), com triagem de falhas por 3 caminhos convergentes (isolado + origem git + leitura de código). Inclui o fluxo de bugfix (confirmar bug real, corrigir, revalidar e reportar ao upstream). Use para validar correções/integrações, diagnosticar teste falhando ou investigar bug no app. Segue a DOUTRINA (.qwen/DESKCOMM-DOUTRINA.md), §1, §5 e §9.
---

# Validação DeskComm — typecheck, lint, unit, E2E e bugfix

**Leia `.qwen/DESKCOMM-DOUTRINA.md` primeiro.** Aqui valem sobretudo: §1 lei dos 3 caminhos, §5 pesquisa profunda (ler código real), §9 validar antes de entregar.

## Bateria de validação

| Fase | Comando | Observação |
|---|---|---|
| Typecheck | `pnpm typecheck` | `tsc --noEmit`; deve sair exit 0 |
| Lint | `pnpm lint` (script default do projeto) | Rodar após typecheck |
| Unit | `pnpm test:unit` (vitest run) | ~2950 testes; 2 falhas ambientais conhecidas no Windows |
| E2E | `pnpm test:e2e` (playwright) ou scripts em `scripts/` | Opera o browser SEM interferência do usuário |

## Falhas ambientais conhecidas do Windows (não são bugs — classificar ANTES de tocar em código)

1. **`spawnSync npx ENOENT`** (`tests/unit/import-puro-sem-env.test.ts`): o teste abre subprocesso `npx tsx` via `execFileSync` sem shell; no Windows o shim `npx.cmd` não resolve. Confirmação: rodar o teste isolado e ver o mesmo erro; o subteste estático do mesmo arquivo passa.
2. **Varredura vazia em teste que usa `grep` do shell** (ex.: `tests/unit/performed-at-um-relogio-so.test.ts`): `grep` não existe no PATH do Windows → `execFileSync` lança → lista vazia → guarda do instrumento estoura. Confirmação: rodar isolado; ver que o teste estático do mesmo arquivo passa.
3. **Timeout em teste de barrel de ícones** (`lib/ui/icons.test.ts`): importa ~1300 módulos; sob suíte paralela com máquina carregada pode estourar os 30s. Confirmação: rodar isolado → passa (~3s). É flakiness de carga, não bug.

**Triagem de QUALQUER falha (obrigatória, 3 caminhos):**
(a) rodar o teste isolado; (b) `git log --oneline -3 -- <arquivo>` para saber origem (fork pré-merge vs upstream); (c) ler o código do teste/módulo. Só com os 3 convergentes classificamos: ambiental, flaky ou bug real.

## Fluxo de bugfix (quando for bug real)

1. Reproduzir com ≥3 evidências (teste E2E no browser + API + logs/banco).
2. Escrever/ajustar teste que capture o defeito ANTES de corrigir (verde-vermelho).
3. Corrigir seguindo as convenções do repo. Não corrigir "de passagem" o que não é o bug.
4. Revalidar: typecheck + lint + unit (com triagem) + teste novo verde.
5. **Reportar ao upstream** (issue no melgarafael/DeskcommCRM com reprodução, ou PR) — item 4 da instrução do usuário.

## E2E operando o browser

- Playwright: `chromium.launch({ channel: "msedge" })` (chrome-headless-shell não instalado; ver skill de operação do Chrome para instalar `npx playwright install chromium` com aprovação).
- Inputs com validação client-side (zod): usar `pressSequentially`, não `fill()` (o `fill` dispara o validador e acusa "Email inválido" — não é bug do app).
- Fluxo login validado: /app/inbox + cookie `sb-deskcomm-auth`. Usuário 2FA novo pede setup = fluxo normal.
- Nunca conectar o número real do WhatsApp em sessão dev (memória "Política de sessão WAHA dev").

## Checkpoint e rollback

- Gravar `.qwen/state/ultima-validacao.json`: fases rodadas, falhas classificadas, evidências.
- Correção que piorou → `git revert` do commit da correção. Browser travado → encerrar o processo do browser e recomeçar.

## Limitações

- Não corrige falha ambiental reescrevendo teste do upstream sem antes documentar/reportar (evita divergir do upstream).
- Falha de infraestrutura (Kong, mounts) delega para a skill `deskcomm-stack-local`.
- Não deploya.
