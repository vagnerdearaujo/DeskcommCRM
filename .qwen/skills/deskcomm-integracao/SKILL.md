---
name: deskcomm-integracao
description: Integra o upstream (melgarafael/DeskcommCRM, origin/main) na branch merge-test/upstream e depois sincroniza o dev. Use quando for atualizar a branch de integração com o mainstream, resolver colisões de migrations (renumeração NNNN), atualizar o MANIFEST.md ou preparar o merge para o dev. Segue a DOUTRINA (arquivo .qwen/DESKCOMM-DOUTRINA.md).
---

# Integração DeskComm com o upstream

Procedimento para integrar `origin/main` (upstream) na `merge-test/upstream`, com validação em cada etapa. **Leia `.qwen/DESKCOMM-DOUTRINA.md` antes de começar.** Regras que mais importam aqui: lei dos 3 caminhos (§1), política fork×upstream (§6), nunca destruir sem 3 opções validadas na branch de integração (§2), continuidade com checkpoint (§10).

## Contexto fixo do projeto

- `origin` = upstream `melgarafael/DeskcommCRM`; `fork/*` = o fork local.
- Branches: `dev` (desenvolvimento), `main`, `merge-test/upstream` (integração).
- Migrations do fork NUNCA colidem com o upstream por NNNN: se colidir, `git mv` do ARQUIVO DO FORK para o próximo número livre (timestamps INTACTOS — são a identidade no `supabase_migrations.schema_migrations`).
- Catraca: `npx vitest run tests/unit/manifest-x-migrations.test.ts` — tem que ficar 6/6 verde. **Nunca** readicionar exceção em DIVERGENCIAS_CONHECIDAS para contornar colisão.

## Fluxo

### 1. Estado de partida
1. `git -C D:\qwenProjects\DeskcommCRM status --short` e `git -C D:\qwenProjects\DeskcommCRM branch --show-current`.
2. Confirmar working tree limpa ou anotar o que há (não descartar nada sem 3 caminhos + aprovação).
3. `git fetch origin` (busca upstream) e `git fetch fork` (se configurado).

### 2. Descobrir o que veio do upstream
4. `git -C D:\qwenProjects\DeskcommCRM log --oneline dev..origin/main` — lista os commits novos do upstream.
5. Anotar hash, PR e título (ex.: `9249e6f2 (#181)`).

### 3. Simular o merge ANTES de tocar a working tree
6. Na `merge-test/upstream`: `git merge-tree --write-tree $(git rev-parse merge-test/upstream) origin/main` — exit 0 = merge limpo; exit ≠ 0 = conflito (o stderr lista os arquivos).
7. Se houver conflito: **parar e reportar ao pai com a lista de arquivos** — não resolver às cegas. Decisões de conflito exigem análise com 3 caminhos (conteúdo de cada lado, histórico, intenção do upstream).

### 4. Merge real e colisão de migrations
8. `git merge --no-ff origin/main -m "merge: upstream <hash> (#<PR>)"` (ou sem `-m` para editar).
9. Rodar a catraca `npx vitest run tests/unit/manifest-x-migrations.test.ts`.
10. Se falhar por NNNN duplicado (ex.: `0110: 0110_recreate_organizations, 0110_lead_checkpoints_declaracao`):
    - Identificar os arquivos DO FORK (nunca os do upstream).
    - Conferir números livres listando `supabase/migrations/`.
    - `git mv <fork>_NNNN_*.sql <fork>_NNNN_novo.sql` preservando o TIMESTAMP do nome (ex.: `20260428195500_0110_...` → `20260428195500_0116_...`).
    - Atualizar as linhas correspondentes no `supabase/migrations/MANIFEST.md`: nome da coluna + texto histórico "Renumerada de X para Y (data) e de Y para Z (data, integração upstream #PR)" com os NNNN que colidiram de cada lado.
    - Rodar a catraca de novo → tem que ficar 6/6 verde.

### 5. Commits atômicos
11. Commit 1: o merge. Commit 2: a renumeração (`fix(migrations): renumera <velhos> para <novos> na integração upstream #<PR>`). Nunca misturar.
12. `git log --oneline -3` para confirmar.

### 6. Validar a integração
13. `pnpm typecheck` e `pnpm test:unit` (ver skill `deskcomm-validacao` para a triagem das 3 falhas ambientais conhecidas).
14. Só depois de verde (ou falhas classificadas como ambientais), sincronizar `dev`: merge da integração validada em `dev` **com aprovação do usuário** (push no fork idem).

### 7. Checkpoint
15. Gravar `.qwen/state/ultima-integracao.json`: hashes (antes/depois), PR integrado, migrations renomeadas, etapas concluídas.

## Rollback

- Merge falhou no meio → `git merge --abort` (working tree volta intacta).
- Merge commitado errado → `git revert` do commit de merge (nunca `reset --hard` em branch com histórico).
- Renumeração errada → `git mv` reverso + revert do MANIFEST (timestamps nunca mudam).

## Limitações

- Não resolve conflito de código por conta própria: para e reporta.
- Não cria exceções na catraca.
- Não faz push sem aprovação explícita do usuário.
- Não toca em banco nem em deploy (skills próprias).
