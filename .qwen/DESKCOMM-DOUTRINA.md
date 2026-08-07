# DOUTRINA DeskComm — regras não-negociáveis

Toda skill e todo agente deste projeto **devem** ler e seguir este documento. Nenhuma instrução de skill/agente pode contradizê-lo; se contradizer, a doutrina vence. Quando a doutrina exigir decisão do usuário, a skill/agente **para e reporta ao agente pai** — nunca decide sozinho.

## 1. Lei dos 3 caminhos (nenhum veredicto sem evidência)

- Nenhum diagnóstico de bug, falha ou decisão de modificação/exclusão é aceito com menos de **3 caminhos convergentes** (ex.: teste isolado + origem no git + leitura do código-fonte + logs + execução de teste).
- **Chutes são proibidos.** "Parece que" não é evidência. Se não der para obter 3 caminhos, diga que não dá e proponha como obter.

## 2. Nunca destruir sem investigar e perguntar

- Qualquer ação destrutiva (rm, drop, delete, truncate, reset --hard, prune, remoção de arquivo/branch/volume/container) exige: (a) investigação prévia com dados reais, (b) **3 opções validadas com testes distintos** (exclusivo para a branch de integração `merge-test/upstream`), (c) aprovação explícita do usuário.
- Isso vale MESMO em modo YOLO ou com permissão automática.
- Em arquivos desconhecidos/inesperados: investigar antes de mexer — pode ser trabalho em progresso do usuário.

## 3. Snapshot + rollback antes de mudar schema de banco

- Antes de aplicar migrations ou alterar schema em banco com dados reais: (1) **snapshot completo** `pg_dump -Fc` com timestamp, (2) aplicação com `ON_ERROR_STOP`, (3) verificação pós-migração, (4) **script de restore** (`pg_restore --clean`) testado e documentado.
- O usuário pergunta explicitamente se isso existe — tem que existir.

## 4. Testar o caminho real de acesso

- Nunca concluir "serviço fora" testando um caminho arbitrário (IP:porta, localhost) sem antes descobrir o caminho real do usuário (nginx vhosts, domínio, Cloudflare, proxy reverso).
- Testar o caminho do usuário primeiro (ex.: `curl -skI https://dominio`), depois o interno — nunca o inverso como única evidência.
- Nunca propor ação invasiva (restart, ufw, docker) com diagnóstico incompleto.

## 5. Pesquisa profunda com dados reais

- Avaliar ferramenta/framework com dados reais (issues GitHub ordenadas por comentários, fóruns), não resumos superficiais.
- **Ler os arquivos de configuração reais do projeto** (docker-compose, .env.example, package.json, código) antes de afirmar requisitos. Distinguir documentação de código-fonte.
- Ser honesto sobre riscos mesmo quando a solução já foi escolhida.

## 6. Política fork × upstream (melgarafael)

- `origin` = upstream `melgarafael/DeskcommCRM`. Conteúdos iguais → manter. Diferentes → **renomear o ARQUIVO DO FORK, nunca o do upstream** (ex.: `git mv` do fork para número livre).
- Migrations: **renumerar, nunca readicionar exceção na catraca**. Timestamps são identidade (`supabase_migrations.schema_migrations`) — renumeração NÃO muda timestamp, então nenhum banco re-aplica.
- Doutrina de migrations: tripla (migration versionada + apêndice no baseline + linha no MANIFEST.md) + catraca `manifest-x-migrations.test.ts` sempre verde.
- Merge no `merge-test/upstream` primeiro; `dev` só depois de validado. Push no fork **só com aprovação explícita do usuário**.

## 7. Segurança de credenciais

- Autenticar serviços (VPS, APIs) por `sessionid`/cookie ou credenciais criptografadas — nunca login/senha digitados no terminal.
- Nunca logar, commitar ou expor secrets. Repos novos no GitHub: **privados por padrão**.

## 8. Deploy e infraestrutura

- Deploy na VPS **só via git** (commit → push → deploy.sh). Nunca SCP do diretório local.
- VPS é **ARM64** — checar plataforma de imagens.
- Não sugerir ngrok (VPS já tem HTTPS; webhooks resolvem via rede interna Docker). Não recomendar EasyPanel.
- Mudanças de firewall: passo-a-passo com verificação entre cada comando — nunca comandos encadeados sem verificação.

## 9. Validação antes de entregar

- Código só é entregue testado (typecheck/lint/unit/E2E conforme o caso). Nunca pedir ao usuário para executar código não validado.
- Falha ambiental Windows conhecida não é bug: classificar com 3 caminhos antes de tocar no código.
- Seguir a especificação exata do usuário — não improvisar fluxo; validar antes de entrar em modo "entregar".

## 10. Continuidade do trabalho

- Operações longas gravam **checkpoint** em `.qwen/state/<operacao>.json` (hashes, etapa atual, próximo passo) para retomar após queda de sessão.
- Passos idempotentes: re-executar não duplica efeito.
- Nunca deixar o repo num estado quebrado: se uma fase falha, abortar limpo (`git merge --abort`, restore de snapshot) ou registrar checkpoint — nunca commit pela metade.
- Se uma skill/agente encontra trabalho fora do próprio escopo, **devolve ao domínio certo** (reporta ao pai) — não resolve fora de domínio.
