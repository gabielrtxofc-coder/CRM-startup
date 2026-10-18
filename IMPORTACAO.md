# Importação e estabilização — CRM da startup

Este repositório contém o **DeskcommCRM** importado como base do CRM da startup, mais o
trabalho de estabilização executado no sandbox do Arena em 2026-10-13.

---

## 1. Procedência

| Item | Valor |
|---|---|
| Repositório de origem | `https://github.com/melgarafael/DeskcommCRM` |
| Branch de origem | `main` |
| Commit de origem | `221cedb45d10ef72b548199728ed99e5cb1f36c3` (2026-10-12, "Merge pull request #2760 from profpeque/feat/EPIC-04-tarefas-no-card") |
| Arquivos importados | 8077 (árvore de trabalho completa do commit acima) |
| Licença | **MIT** — `LICENSE` preservado na raiz, sem alteração |
| Titular dos direitos | Rafael Melgaço (copyright 2026), conforme `LICENSE` |
| Repositório de destino | `gabielrtxofc-coder/CRM-startup` |
| Branch de trabalho | `arena/8a1c4da3-crm-startup` (a sessão do Arena é fixa nesta branch) |
| Origem modificada? | **Não.** O clone de origem foi apenas lido. |

### Atribuição exigida pela MIT

A licença MIT permite usar, copiar, modificar, mesclar, publicar, distribuir,
sublicenciar e vender cópias, com uma condição: o aviso de direitos autorais e o aviso
de permissão devem acompanhar todas as cópias ou partes substanciais do software.
Ambos estão em `LICENSE`, na raiz, byte-idênticos ao arquivo do projeto de origem.
Este documento registra adicionalmente a procedência e o commit exato importado.

## 2. O que entrou e o que ficou de fora

**Entrou:** a árvore de trabalho inteira do commit de origem — código (`app`, `lib`,
`components`, `hooks`, `workers`, `scripts`, `supabase`, `tests`), configuração
(`package.json`, `pnpm-lock.yaml`, `next.config.ts`, `tsconfig*.json`, `vitest*.ts`,
`playwright.config.ts`, `eslint.config.mjs`), infraestrutura (`Dockerfile*`,
`docker-compose*.yml`, `Caddyfile*`, `hostgator-setup-kit`, `infra`), documentação
(`README*.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `docs`, `AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING*.md`, `SECURITY.md`, `VISION.md`) e o acervo de evidências versionado
(`evidence`, `docs/evidence`).

`evidence/` (94 MB) foi mantido **de propósito**: `tests/unit/evidencia-citada.test.ts`
exige que toda imagem citada num documento versionado exista no repositório, e o inverso.
Retirar o acervo quebraria a suíte e apagaria o lastro das afirmações dos documentos.

**Ficou de fora:**

| Item | Motivo |
|---|---|
| `.git` da origem (269 MB, 130+ branches) | O destino mantém o próprio histórico a partir de `Initial commit`. A procedência fica neste arquivo e na mensagem do commit de importação. |
| `.env`, `.env.local`, `.env.e2e` | Nenhum estava versionado na origem. Os únicos arquivos de ambiente do repositório são os templates `.env.example`, `.env.hostgator.example` e `.env.voip.example`. |
| `node_modules`, `.next`, `test-results`, `playwright-report` | Dependências instaladas e artefatos de build; `.gitignore` já os cobre. |
| Credenciais, bancos de dados, dados de clientes | Nada disso existe no repositório de origem. Varredura por segredos (chaves `sk-*`, JWT, chaves privadas, `AKIA*`, `ghp_*`, tokens Slack) não achou credencial real: os únicos acertos são fixtures de teste com valores declaradamente falsos e as chaves demo públicas do Supabase. |

### Conteúdo preexistente no destino

O destino tinha um único arquivo, `README.md`, com o conteúdo placeholder
`# CRM-startup` (13 bytes, commit `fee27a6`). Ele foi substituído pelo README do
projeto importado; o conteúdo anterior permanece no histórico da branch `main` e está
transcrito aqui. Nenhuma outra alteração preexistente existia a preservar.

## 3. Estado da estabilização (medido em 2026-10-13, sandbox Arena)

Ambiente: Node 22.22.3, pnpm 9.15.9 (o fixado em `packageManager`), 2 vCPU, 3,9 GB RAM
(+6 GB de swap criados nesta sessão), Debian 12, **sem Docker** e sem rede para
`*.supabase.co`, Docker Hub, `deb.debian.org` e CDN do Playwright.

| Verificação | Comando | Resultado |
|---|---|---|
| Instalação de dependências | `pnpm install --frozen-lockfile` | **PASSOU** — 942 pacotes, exit 0, 21,9 s |
| Guardas estruturais | `pnpm cercas` | **PASSOU** — 307 arquivos, 2959 testes, exit 0 |
| Suíte unitária | `pnpm test:unit` | **PASSOU após 1 correção** — antes: 22941✓/1✗ (22945 testes); depois, suíte completa re-executada: **22943✓ / 1 xfail / 2 skip (22946 testes), 2194 arquivos + 1 pulado, 0 falhas**, 52 min |
| Tipos | `pnpm typecheck` | **PASSOU** — exit 0 (exigia heap > 3 GB; desde 16/10 o heap vem embutido no script — §6.3, P4) |
| Lint | `pnpm lint` | **PASSOU** — exit 0, 0 erros, 537 warnings preexistentes |
| Build de produção | `pnpm build` | **PASSOU** — exit 0, 626 rotas, 63 páginas estáticas |
| App em dev | `next dev` | **PASSOU** — Ready em 699 ms; rotas públicas, guardas de auth e API respondendo |
| App em produção | `node .next/standalone/server.js` | **PASSOU** — Ready; `/app/inbox` autenticado renderiza 79 KB de HTML |
| Invariantes de banco | `pnpm test:db` | **NÃO EXECUTADO** — exige Docker (ver §5; medido sem Docker em §6.4) |
| E2E Playwright | `pnpm test:e2e` | **NÃO EXECUTADO** — exige Supabase local (Docker) e browsers baixados de CDN bloqueada |

### Correção aplicada

`lib/messaging/media/url-de-midia-externa.test.ts` — o caso anti-SSRF "recusa Storage de
outra origem" fixava `http://127.0.0.1:54321/...` como exemplo de origem estrangeira.
54321 é justamente a porta do Supabase local que o projeto documenta
(`docs/specs/08-spec-deploy-observability.md`, `infra/executor-proprio/README.md`,
`docs/handoffs/HANDOFF-indice-de-atrito.md`). Como `tests/setup/vitest.setup.ts` carrega
`.env`/`.env.local` do disco e o valor real vence o placeholder do CI, quem roda a suíte
com o setup local documentado recebe um vermelho falso **num teste de segurança**: a
guarda aceita a URL porque ela é, de fato, a origem assinada da instalação.

A correção é só no fixture: `origemPrivadaEstrangeira()` escolhe a primeira porta entre
54321/54322/54323 que não coincide com `env.NEXT_PUBLIC_SUPABASE_URL`, mais uma trava
explícita que reprova se o fixture voltar a colidir. Nenhum código de produto mudou.
Verificado nos três ambientes (54321, 54322 e origem não-loopback): 8 testes passam.

## 4. Como executar

### Desenvolvimento

```bash
corepack enable && corepack prepare pnpm@9.15.9 --activate
pnpm install --frozen-lockfile
cp .env.example .env.local      # e preencha as três variáveis obrigatórias
pnpm dev                        # http://localhost:3000
```

Obrigatórias em **qualquer** ambiente (`lib/env.ts` lança na importação se faltarem):
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`.

### Produção (o caminho da imagem Docker)

```bash
pnpm build
cp -a .next/static .next/standalone/.next/static
cp -a public .next/standalone/public
cd .next/standalone && HOSTNAME=0.0.0.0 PORT=3000 node server.js
```

Em produção (`NODE_ENV=production`) o `lib/env.ts` cobra, além das três acima, mais nove
variáveis: `CPF_ENCRYPTION_KEY`, `WAHA_BYO_ENCRYPTION_KEY`, `AI_CRED_AES_KEY`,
`SUPABASE_DB_URL`, `WAHA_API_BASE_URL`, `WAHA_API_KEY`, `WAHA_WEBHOOK_BASE_URL`,
`UPSTASH_REDIS_REST_URL` e `UPSTASH_REDIS_REST_TOKEN`. Sem elas **toda** requisição
responde 500 (o middleware lança na avaliação do módulo). O
`hostgator-setup-kit/install.sh` gera todas automaticamente.

`next start` **não** é o entrypoint deste projeto: `next.config.ts` usa
`output: "standalone"` e o próprio Next avisa
(`"next start" does not work with "output: standalone"`). Use `node .next/standalone/server.js`.

### Testes

```bash
pnpm cercas        # guardas estruturais (rápido, sem DOM)
pnpm test:unit     # suíte completa
pnpm typecheck     # o heap de 6 GB já vem embutido no script (antes: NODE_OPTIONS à mão) — §6.3, P4
pnpm lint
pnpm test:db       # requer Docker
bash scripts/test-db-sem-docker.sh test:db   # sem Docker, PostgreSQL 16 local (opcional; limites em §6.4)
pnpm test:e2e      # requer Supabase local (Docker) + browsers do Playwright
```

## 5. Limitações conhecidas deste ambiente

- **Invariantes de banco (447 arquivos) não rodam sem Docker** *(atualizado em §6.4: há um caminho sem Docker, com limites declarados)*. `scripts/test-db.sh` sobe
  `pgvector/pgvector:pg15` e `tests/db/banco-limpo-por-arquivo.ts` chama `docker exec`.
  Alternativas avaliadas e descartadas, com o motivo medido: `embedded-postgres` (npm) não
  traz `psql` nem `contrib`; `pgserver` (PyPI) traz PostgreSQL 16.2 com `psql`, mas o
  diretório `share/extension` vem vazio (sem `pgcrypto`, que o `supabase/baseline.sql`
  usa em 21 pontos); `@serve-tools/postgres` (npm) traz PostgreSQL 18.4 completo com
  `pgcrypto`, `uuid-ossp`, `citext` e `pg_trgm`, mas **sem `pgvector`** e sem headers de
  servidor para compilá-lo; `postgresql-wheel` (PyPI) só vai até PostgreSQL 14 com
  Python < 3.10, abaixo do piso pg15 do baseline. Como `vector` aparece em
  `retrieve_top_k_chunks`, em `ai_chunks.embedding vector(1536)` e no índice `ivfflat`,
  stubá-lo produziria um harness que não é o banco do produto — e vermelho nesse harness
  não seria evidência de defeito.
- **E2E Playwright não roda.** `scripts/gerar-env-e2e.sh` exige `supabase status` de pé
  (Docker) e os browsers vêm de CDN fora da lista de hosts permitidos.
- **Persistência entre reinícios não foi verificada**: sem banco real, não há o que
  persistir. As operações de CRUD foram verificadas quanto a contrato, validação,
  autorização e escopo de tenant — não quanto a gravação durável.
- **Serviços externos não exercitados de verdade**: WAHA (WhatsApp), provedores de IA,
  Upstash Redis, Resend, Sentry, Nuvemshop e Google. O `/api/v1/health` os reporta como
  `down`/`nao_configurado`, que é o comportamento esperado sem configuração.
- **`pnpm typecheck` precisa de heap grande** *(corrigido em §6.3, P4: o heap agora vem no script)*. Com o padrão do Node em máquina de 3,9 GB
  o `tsc` morre com `JavaScript heap out of memory` (exit 134) aos 36 s; com
  `--max-old-space-size=3072` morre de novo aos 75 s; passou com 6144 MB + swap
  (exit 0 em 3m42s). Não é defeito do código — é requisito de memória do gate.

---

## 6. Continuidade — testes e correções (2026-10-16)

Retomada sobre a `main` @ `1bed87a`: árvore limpa, nada pendente. Os únicos registros anteriores
eram o PR #1 (§3) e o histórico do GitHub Actions, lido em 6.1. Ambiente: o de §3 (Node 22.22.3,
pnpm 9.15.9, 2 vCPU, 3,9 GB de RAM + 6 GB de swap recriados), **sem Docker**. Tudo o que está
aqui foi executado; o que não foi está em 6.6. **Nada foi mesclado, lançado ou implantado**: as
mudanças seguem num PR *draft*, a partir da branch de trabalho; a `main` não foi tocada.

### 6.1 O que o GitHub Actions dizia antes de qualquer mudança

Lido pela API do Actions. Os *logs* e artefatos ficam em hosts fora da lista permitida do sandbox,
então só há conclusões, durações e anotações — nunca a mensagem de erro do job.

| Execução | Resultado |
|---|---|
| `ci` e `e2e`, push da `main` (13/10, `1bed87a`) | `verify` ✅ (4 partes, 5–10 min) · `build-and-size` ✅ · **`invariants` ❌** (pg15 e pg17: o passo `RLS isolation + governance invariants` cai em **16–27 s**; o `test:db:update` seguinte fica *pulado*) · **`e2e` ❌** (só a parte 2, após ~20 min; as outras cinco ✅) |
| PR #1, `d903fcc` (mesma árvore) | `verify` ✅ · `invariants` ❌ · `e2e` ✅ (a parte 2 passou) |
| PR #3 (Dependabot, `@types/jest` 30) | só `invariants` ❌ |
| PR #4 (Dependabot, 14 bumps) | `invariants` ❌ · `verify-parte (1)` cancelada no teto de 15 min · `verify-parte (2)` ❌ em `Unit tests (parte 2/3)` |

### 6.2 Medido nesta sessão, antes de qualquer mudança

| Verificação | Comando | Resultado |
|---|---|---|
| Dependências | `pnpm install --frozen-lockfile` | ✅ exit 0, 15,7 s |
| Guardas estruturais | `pnpm cercas` | ✅ 307 arquivos / 2959 testes (181 s) |
| Auditorias | `pnpm lint:channels` · `pnpm lint:role-rank` · `pnpm checar:colisao-de-migration` | ✅ ✅ ✅ |
| Kit self-host | `pnpm test:shell` | ✅ 43 scripts, todos exit 0 (§3 não tinha medido este passo, que é a parte 4 do CI) |
| Tipos | `pnpm typecheck` | ✅ 258 s com `NODE_OPTIONS=--max-old-space-size=6144` · ❌ **exit 134 em 36 s a frio e sem a variável** |
| Lint | `pnpm lint` | ✅ 0 erros, 537 warnings (o mesmo número de §3) |
| Unitários | `pnpm vitest run --project produto` (as cercas rodaram acima) | ❌ **1 falha**: 1888 arquivos → 1886 ✅, 1 pulado, 1 ❌; 19.987 testes → 19.984 ✅, 1 ❌, 1 xfail, 1 skip (51,6 min) |
| Banco | `pnpm test:db`, `pnpm test:db:update` | não rodam sem Docker → 6.4 |

Somando cercas e `produto`: 2195 arquivos e 22.946 testes — os mesmos números do PR #1. A diferença
é uma só: o PR #1 registrou 0 falhas; hoje há 1.

### 6.3 Problemas encontrados e correções

**P1 — o check obrigatório `invariants` fica vermelho em todo run: o gate pressupõe um repositório
com releases.** `scripts/test-db.sh` termina chamando `scripts/conferir-isolamento-do-kit.sh`, que
exige uma "última release publicada" no `origin` e busca nele a tag fixa `v1.63.0`. Este
repositório nasceu da importação sem tags e sem releases (`gh release list` e
`git ls-remote --tags origin` vazios). Resultado: `FATAL: não consegui saber qual é a última
release publicada`, exit 1, antes de qualquer invariante rodar. **Reproduzido** com o mesmo
`pnpm test:db` num PostgreSQL local (6.4): o baseline instala e é reaplicado com zero erro, e o
script morre nesse passo em 9 s — o passo e a janela de 16–27 s vistos no Actions.
*Correção* (`scripts/conferir-isolamento-do-kit.sh`): o `origin` continua sendo a primeira fonte,
para a release e para cada tag; só quando ele não sabe a pergunta vai ao upstream
(`melgarafael/DeskcommCRM`; `CONFERENCIA_KIT_UPSTREAM*` trocam), com aviso no stderr. Sem resposta
de nenhuma fonte, reprova do mesmo jeito — o fallback acrescenta uma fonte, não afrouxa a regra.
Com dados reais e o `origin` apontando para o GitHub, num clone raso (como o checkout do CI): release
resolvida `v1.83.0` e as três conferências (`update.sh` do checkout, da última release e da
`v1.63.0`) passam, **166 regras declaradas, todas no banco**. Teste de regressão novo e offline,
`tests/shell/conferencia-do-kit-sem-release-no-origin.test.sh`: 24 checagens verdes; contra o script
original, 15 falham.

**P2 — teste com data absoluta que venceu (reprova hoje).** `tests/unit/conversao-pelo-canal.test.ts`
fixa `ENTROU_NA_ETAPA = 2026-10-06T16:32:50Z`, e o transporte direto da Meta recusa evento com mais
de 7 dias (`IDADE_MAXIMA_MS`, `lib/plataformas-de-anuncio/meta/conversions.ts`). O caso "com a
conexão direta ligada, a etapa segue por ela" passou a reprovar sozinho a partir de 13/10 às
16:32Z, sem mudança de código — o `verify` desta árvore, verde em 13/10, estaria vermelho hoje. O
produto está certo; o fixture é que vence. *Correção:* relógio fixado no bloco da etapa
(`vi.useFakeTimers({ toFake: ["Date"] })` + `vi.setSystemTime`), o padrão que 16 outros arquivos de
teste já usam.

**P3 — teste com data absoluta que vence em 01/01/2027.**
`app/api/v1/proposals/[id]/send/route.test.ts`, achado por "viagem no tempo" (abaixo): com o relógio
em 25/12/2026 os 49 casos passam; em 04/01/2027, 3 reprovam. O fixture traz
`valid_until: "2026-12-31"` e a rota só agenda o retorno automático se ele cair dentro da validade
(`dentroDaValidade`, em `route.ts`). *Correção:* validade relativa ao relógio (hoje + 90 dias).
*Como se achou:* um `setupFile` fora do repositório (`/tmp`) adianta só o `Date` em N dias
(`vi.useFakeTimers({ toFake: ["Date"], now: Date.now() + N dias, shouldAdvanceTime: true })`) e
roda os arquivos com literal de data 2026 que não simulam o relógio por conta própria (751; 691 no
projeto `produto`). **+30 dias** (15/11/2026): só P2 falha. **+400 dias** (20/11/2027): só P2 e P3
falham (2 arquivos, 4 testes); os outros 689 passam (8277 testes). Fora do repositório; a sonda que
confirma o deslocamento (`new Date()` = real + N dias) foi conferida antes de confiar no "limpo".

**P4 — `pnpm typecheck` morre a frio com o heap padrão.** O CI injeta
`NODE_OPTIONS=--max-old-space-size=6144` só no passo dele; o script que o `AGENTS.md` manda rodar não
tem, e o cache incremental (`tsconfig.typecheck.tsbuildinfo`) esconde o defeito de quem já rodou uma
vez com mais memória. **Reproduzido:** sem cache e sem a variável, exit 134 em 36 s
(`JavaScript heap out of memory`, limite de 1954 MB aqui). *Correção:* o script passou a
`node --max-old-space-size=6144 ./node_modules/typescript/bin/tsc --noEmit -p tsconfig.typecheck.json`
(portável; o `NODE_OPTIONS` do CI continua e não conflita). A frio e sem variável: exit 0 em 261 s.

### 6.4 Invariantes de banco sem Docker

Sem Docker, `pnpm test:db` morre em `docker: command not found`. O que se montou, e que está em
`scripts/test-db-sem-docker.sh` (opcional, fora do caminho do produto): PostgreSQL 16.14 de binários
oficiais (wheel `pixeltable-pgserver` do PyPI, fixado por versão **e SHA-256**), com o pgvector do
próprio wheel; `pgcrypto`, `citext` e `pg_trgm` compilados da fonte oficial da mesma versão; um dublê
de `docker` (`run`, `port`, `exec`, `rm` — o que `test-db.sh`, `test-update-com-dados.sh` e os
invariantes usam) que mapeia "container" para um cluster descartável. Uso:
`bash scripts/test-db-sem-docker.sh preparar` (uma vez, ~30 s) e depois
`bash scripts/test-db-sem-docker.sh test:db` ou `test:db:update`.

**Não substitui o CI.** Diferenças, também declaradas no cabeçalho do script: PostgreSQL 16 (o CI
mede 15 e 17); sem libxml; `uuid-ossp` substituído por SQL (`uuid_generate_v4` → `gen_random_uuid`,
a única função de UUID que o baseline usa); collation `C.UTF-8` (a imagem do CI usa `en_US.utf8`);
`fsync` desligado.

Resultados (script de P1 corrigido, clone raso, `GH_TOKEN` como no job):

| Comando | Resultado |
|---|---|
| `pnpm test:db` | 439 arquivos → 438 ✅, 1 ❌; 3433 testes → **3431 ✅**, 1 ❌, 1 pulado (13,7 min) |
| `pnpm test:db:update` | ✅ exit 0: instala, semeia dados, reaplica o baseline sobre eles, OIDs de views estáveis, dados sobrevivem |

O único vermelho é `harness-isola-por-arquivo.test.ts › o banco recebido está no estado do molde`:
`ERROR: unsupported XML feature` — o teste usa funções XML do SQL (é o único arquivo que usa) e o
PostgreSQL do wheel não tem libxml. Artefato do harness, não do produto.

### 6.5 Depois das correções

| Verificação | Resultado |
|---|---|
| Os 2 testes de P2 e P3 | ✅ 71/71 no relógio real e simulado em +0, +80 (04/01/2027) e +400 dias; antes: ❌ hoje (P2) e ❌ a partir de 01/01/2027 (P3) |
| Teste novo do gate (P1) | ✅ 24 de 24; contra o script original: 15 ❌ |
| `conferir-isolamento-do-kit.sh`, clone raso, `origin` = GitHub | ✅ 3 conferências, 166 regras; antes: `FATAL`, exit 1 |
| `pnpm test:shell` | ✅ exit 0 (44 scripts, 206 s) |
| `pnpm cercas` | ✅ 307 arquivos / 2959 testes |
| `pnpm lint` | ✅ 0 erros, 537 warnings (igual ao de antes) |
| `pnpm typecheck` a frio, sem `NODE_OPTIONS` | ✅ exit 0 em 261 s; antes: exit 134 |
| 19 testes que leem `package.json` | ✅ 147/147 |
| PR #4 do Dependabot (14 bumps), `produto` com o lockfile dele, fatias 1/3 e 2/3 (clone raso em `/tmp`) | fatia 1: ✅ 629 arquivos, 6404 testes, 0 falhas · fatia 2: 628 ✅ + 1 ❌ = **a mesma bomba de P2**, não os bumps · a fatia 3 passou no CI. O teto estourado na parte 1 do CI parece ser de máquina lenta (indício, não medição direta): `Typecheck` 169 s contra 98 s no run da `main`, unitários cancelados aos 703 s contra 489 s — e localmente nenhum teste falha nem trava |
| Suíte `produto` inteira | **não repetida** (51 min). A única falha era P2; os arquivos alterados e os guardas afetados foram reexecutados como acima |

### 6.6 O que continua sem medir e o que depende de decisão humana

Sem medir:

- **E2E Playwright** (180 specs + 7 jornadas): exige Supabase local (Docker) e browsers de uma CDN
  bloqueada. A parte 2 vermelha da `main` (exit 1; `retries: 0` no `playwright.config.ts`) passou em
  outros runs da mesma árvore — flake provável, mas sem o log não dá para dizer qual spec. 19 specs
  e 50 invariantes de banco misturam data absoluta e relógio real
  (`grep -lE '2026-[01][0-9]-[0-3][0-9]' tests/e2e/*.spec.ts | xargs grep -lE 'Date\.now\(\)|new Date\(\)'`):
  candidatas ao mesmo defeito de P2/P3. As invariantes passaram hoje, mas não foram atravessadas no
  tempo; os specs, nem hoje.
- **pg15 e pg17**, que o CI mede; aqui só o 16.
- **Serviços externos** (WAHA, IA, Redis, Resend, Sentry, Nuvemshop, Google) e CRUD contra um Supabase
  de verdade (Auth, Realtime, Storage).
- **O CI do GitHub não tinha rodado com as correções quando esta seção foi escrita**: "deve ficar
  verde" abaixo é inferência a partir das medições locais; o resultado do Actions está nos checks e
  nos comentários do PR, não aqui.

Depende de decisão ou ação do dono:

1. **Releases e tags.** O repositório não tem nenhuma. `update.sh` e `agent.sh` descobrem a versão-alvo
   por `ultima_release_estavel` (o `/releases/latest` do `origin`), que devolve vazio aqui: uma
   instalação deste repositório não sabe qual versão buscar até existir a primeira release (workflow
   `release`, disparo manual) ou `DESKCOMM_RELEASES_LATEST_URL` apontar para outro lugar. P1 resolve o
   *gate*; não resolve isto.
2. **Identidade da instalação.** `hostgator-setup-kit/install.sh` (`REPO_URL`), `_common.sh` (`IMG_NS`)
   e `docker-compose.prod.yml` ainda apontam para o upstream e suas imagens (`ghcr.io/melgarafael/…`).
   Instalar "este" CRM numa VPS hoje instala o código e as imagens do upstream. Trocar exige decidir
   o namespace e publicar imagens próprias.
3. **PRs do Dependabot (#3 e #4).** O #3 só estava vermelho em `invariants`, no mesmo passo e na mesma
   duração de P1 (17 s), com `verify` ✅. O #4 estava vermelho por P1 + P2 (o `Unit tests (parte 2/3)`)
   + um teto de tempo estourado (indício: máquina lenta); localmente, com as dependências dele, só a bomba P2
   falha. Nada medido aponta os bumps como causa — depois de P1 e P2 na `main`, ambos devem ficar
   verdes, mas quem decide mesclar é o dono.
4. **`ubuntu-latest` vira Ubuntu 26 em 19/10/2026** (aviso do GitHub nas anotações dos jobs): pode
   mudar o comportamento dos workflows; não medido.
5. As 9 variáveis obrigatórias de produção (§4) e o aceite das mudanças desta seção (PR draft, sem
   merge).
