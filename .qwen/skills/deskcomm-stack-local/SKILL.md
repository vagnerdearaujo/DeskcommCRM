---
name: deskcomm-stack-local
description: Opera e recupera a stack local do DeskComm no Windows — supabase start/stop, auxiliares docker compose (WAHA 3030, agent-worker 8787, SRH 8081, Redis 6379), e TODOS os quirks conhecidos do Docker Desktop (mount /run/desktop/mnt/host morre com piscada do hub USB, Kong poluído pós-mount-morto, junctions NTFS .temp e data\redis apontando para C:). Use quando a stack não sobe, login falha com AuthRetryableError (Kong morto), ou containers/portas estiverem fora do esperado. Segue a DOUTRINA (.qwen/DESKCOMM-DOUTRINA.md), §4 (caminho real) e §2 (não destruir).
---

# Stack local DeskComm — operação e recuperação (Windows/Docker Desktop)

**Leia `.qwen/DESKCOMM-DOUTRINA.md` primeiro.** Aqui valem sobretudo: §4 testar o caminho real, §2 nunca destruir sem 3 opções validadas, §9 validação antes de entregar.

## Topologia (verificada nesta máquina)

- Stack Supabase via CLI: Kong 54321 (API), Postgres 54322, Studio 54323. Projeto `deskcomm-crm` (config em `supabase/config.toml`).
- Auxiliares via docker compose: WAHA (3030), agent-worker (8787), SRH (8081), Redis (6379).
- App dev: porta 3000, `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` (main) ou `54421` (dev).
- Login: `signInWithPassword` → Kong 54321. **`AuthRetryableFetchError: fetch failed` = Kong morto.**
- Quirk Docker Desktop Windows: bind de arquivos individuais só funciona do C:; o mount `/run/desktop/mnt/host` MORRE quando o hub USB pisca (restart do Docker Desktop não remonta). Junctions NTFS: `.temp`→C: e `data\redis`→C:.

## Diagnóstico (sempre nesta ordem — caminho real primeiro)

1. `docker ps -a` — quais containers existem e em que estado.
2. Portas: Kong `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:54321/auth/v1/health` (esperado 200) e auxiliares.
3. Se Kong morto: `docker logs supabase_kong_deskcomm-crm` (ver erro 127/mount) e verificar mount do host: `docker run --rm -v D:\qwenProjects\DeskcommCRM\supabase\templates:/t alpine ls /t`.
4. **Nunca** `docker system prune`, remoção de volumes ou `rm -rf` de diretórios como primeiro passo.

## Recuperações conhecidas (fixes validados nesta máquina)

### A. Mount `/run/desktop/mnt/host` morto (piscada do hub USB)
1. `wsl --shutdown` (aprovado pelo usuário como fix) → remonta.
2. Confirmar com o teste do `alpine ls /t` acima.

### B. Kong poluído pós-mount-morto ("not a directory" / "file exists" / Exited 127)
1. `docker rm supabase_kong_deskcomm-crm` (Kong é stateless — seguro; binds vêm dos arquivos em disco).
2. `supabase stop` seguido de `supabase start` — **`supabase start` sozinho NÃO recria container removido** (responde "already running" e não age).
3. Validar: health 200 no 54321 + login real no app (ver skill `deskcomm-validacao`).

### C. Junctions NTFS quebradas
1. Verificar `D:\qwenProjects\DeskcommCRM\.temp` e `data\redis` apontando para C: (`dir` mostra a junção).
2. Recriar apenas se confirmado quebrado e com dados preservados no alvo — nunca apagar o alvo.

### D. Porta ocupada / container auxiliar fora
1. Identificar o dono da porta com 3 caminhos (docker ps, netstat, logs).
2. Só então ação específica (restart do container específico, nunca kill em massa).

## Checkpoint

- Gravar `.qwen/state/ultima-stack.json`: containers esperados × presentes, portas testadas, fixes aplicados, próximo passo.

## Limitações

- Não instala software no sistema sem aprovação do usuário.
- Não altera `supabase/config.toml` sem passar pela doutrina.
- Não roda no VPS (skill `deskcomm-deploy-vps`).
