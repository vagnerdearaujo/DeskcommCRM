---
name: deskcomm-deploy-vps
description: Publica o DeskComm na VPS (ARM64) exclusivamente via git — commit, push e deploy.sh — com verificação pós-deploy NO CAMINHO REAL de acesso (Cloudflare → nginx 443 → vhosts → container), tag por release e rollback via deploy.sh --rollback. Use para publicar DEV/Main na VPS, verificar deploy, diagnosticar serviço "fora" ou fazer rollback de produção. Segue a DOUTRINA (.qwen/DESKCOMM-DOUTRINA.md), §4 (caminho real), §7 (credenciais) e §8 (deploy git).
---

# Deploy DeskComm na VPS — via git, com verificação no caminho real

**Leia `.qwen/DESKCOMM-DOUTRINA.md` primeiro.** Aqui valem sobretudo: §4 testar o caminho real (lição do incidente n8n/ufw 2026-08-06), §7 credenciais (sessionid/criptografadas, nunca login/senha no terminal), §8 deploy só via git, firewall passo-a-passo.

## Fatos da VPS (verificados 2026-08-05)

- VPS é **ARM64**; acesso real via Cloudflare → nginx 443 → vhosts → proxy para container/porta interna.
- Portas expostas diretas (IP:porta) NÃO são o caminho real — o usuário acessa por domínio. Fase de blindagem previa fechar 5678/9443 direto.
- Deploy: **commit → push → deploy.sh**. Nunca SCP do diretório local (memória deploy-por-git).
- Webhooks resolvem via rede interna Docker (não usar ngrok).
- Sem EasyPanel (memória nao-recomendar-easypanel).

## Fluxo de deploy

### 1. Pré-flight
1. Working tree do repo limpa e código validado (skill `deskcomm-validacao`) — nunca deployar código não validado.
2. Conferir qual imagem/plataforma o deploy.sh usa (ARM64) — `uname -m` na VPS se necessário.
3. Conferir credenciais: sessionid/cookie ou arquivo criptografado — nunca senha digitada no comando.

### 2. Publicar
4. Commit + `git push` da branch de produção (main/DEV conforme o fluxo aprovado).
5. Tag de release: `git tag deploy-<data>-<hora>` + push da tag.
6. Rodar o deploy na VPS pelo caminho estabelecido (deploy.sh no repo/scripts do host — checar com a memória vagnercoach/deploy de cada serviço).

### 3. Verificação pós-deploy (obrigatória, caminho real)
7. **Primeiro** o caminho do usuário: `curl -skI https://<dominio>` (esperado 200/301+redirecionamento final OK).
8. Depois interno: health do container, logs sem erro novo.
9. Teste funcional mínimo (login, página principal) conforme o caso.
10. Só declarar sucesso com os 3 caminhos (HTTP no domínio + container + log/funcional).

### 4. Rollback (se algo quebrar)
11. `deploy.sh --rollback <tag-anterior>` (pipeline único — mesmo caminho do deploy, sem passos manuais inventados).
12. Re-verificar no caminho real antes de declarar restaurado.

## Firewall (regra rígida)

- Mudança de firewall: **um comando por vez, com verificação entre cada um**. Nunca comandos encadeados sem verificação (memória do incidente ufw 2026-08-06).
- Antes de qualquer ação invasiva (restart docker/ufw/nginx): diagnóstico completo no caminho real + confirmação de que a ação resolve o problema do usuário.

## Checkpoint

- Gravar `.qwen/state/ultimo-deploy.json`: hash deployado, tag, domínios verificados (código HTTP), rollback disponível.

## Limitações

- Não instala/atualiza pacotes na VPS sem aprovação.
- Não mexe em firewall sem o fluxo passo-a-passo acima.
- Não roda migrations de banco em produção (skill `deskcomm-migrations` é local; produção tem separação explícita e aprovação).
