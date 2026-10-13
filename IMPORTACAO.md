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
| Tipos | `pnpm typecheck` | **PASSOU** — exit 0 (exige heap > 3 GB; ver §5) |
| Lint | `pnpm lint` | **PASSOU** — exit 0, 0 erros, 537 warnings preexistentes |
| Build de produção | `pnpm build` | **PASSOU** — exit 0, 626 rotas, 63 páginas estáticas |
| App em dev | `next dev` | **PASSOU** — Ready em 699 ms; rotas públicas, guardas de auth e API respondendo |
| App em produção | `node .next/standalone/server.js` | **PASSOU** — Ready; `/app/inbox` autenticado renderiza 79 KB de HTML |
| Invariantes de banco | `pnpm test:db` | **NÃO EXECUTADO** — exige Docker (ver §5) |
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
pnpm typecheck     # exige NODE_OPTIONS=--max-old-space-size=6144 em máquinas de 4 GB
pnpm lint
pnpm test:db       # requer Docker
pnpm test:e2e      # requer Supabase local (Docker) + browsers do Playwright
```

## 5. Limitações conhecidas deste ambiente

- **Invariantes de banco (447 arquivos) não rodam sem Docker.** `scripts/test-db.sh` sobe
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
- **`pnpm typecheck` precisa de heap grande.** Com o padrão do Node em máquina de 3,9 GB
  o `tsc` morre com `JavaScript heap out of memory` (exit 134) aos 36 s; com
  `--max-old-space-size=3072` morre de novo aos 75 s; passou com 6144 MB + swap
  (exit 0 em 3m42s). Não é defeito do código — é requisito de memória do gate.
