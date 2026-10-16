#!/usr/bin/env bash
# Prova de `scripts/conferir-isolamento-do-kit.sh` num repositório SEM release e SEM
# tag (fork, cópia importada): ele pergunta ao upstream — e, sem resposta de NENHUMA
# fonte, REPROVA do mesmo jeito.
#
#   bash tests/shell/conferencia-do-kit-sem-release-no-origin.test.sh
#
# ── O defeito que ele guarda ────────────────────────────────────────────────
#
# O repositório da startup nasceu de uma importação do upstream (melgarafael/
# DeskcommCRM) SEM as tags e SEM as releases. O `test:db` chama esta conferência
# depois de aplicar o baseline, e ela exigia uma "última release publicada" no
# `origin` e a tag v1.63.0 buscada nele: sem as duas, saía com
# "FATAL: não consegui saber qual é a última release publicada" — e o check
# obrigatório `invariants` ficava vermelho em TODO run (main e PRs, 16–27 s cada,
# medido no Actions em 2026-10-13/14), sem dizer nada sobre schema. O segundo passo
# do job (`test:db:update`) ainda era PULADO por causa disso.
#
# Nada aqui toca a rede nem o Docker: o origin e o upstream são repositórios git
# locais, a "API" é um JSON em `file://`, e o `update.sh` de cada tag é um stub com
# os dois marcadores que o script recorta (`E AS REGRAS DE ISOLAMENTO SÃO
# CONFERIDAS` e a primeira atribuição de `faltando`) e nenhuma consulta ao banco.
set -uo pipefail
# Zera o ambiente git herdado (GIT_DIR de hook ou rebase --exec) e passa a
# identidade por variável: nada aqui escreve no repositório de quem roda.
unset $(git rev-parse --local-env-vars)
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.t
# Config global/de sistema do git de quem roda (hooksPath, gpgsign, url.insteadOf…)
# não pode entrar nestes repositórios descartáveis.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# O ambiente de quem roda (CI, dev com token) decide o caminho do script; aqui cada
# caso declara o seu.
unset GH_TOKEN GITHUB_TOKEN CONFERENCIA_KIT_RELEASE CONFERENCIA_KIT_UPSTREAM \
  CONFERENCIA_KIT_UPSTREAM_GIT CONFERENCIA_KIT_UPSTREAM_API DESKCOMM_RELEASES_LATEST_URL

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
check() {  # check <descrição> <comando...>
  if "${@:2}"; then printf '  ✓ %s\n' "$1"; else printf '  ✗ %s\n' "$1"; FAILS=$((FAILS + 1)); fi
}
# Asserções sobre a última execução (`rodar` deixa $COD, $OUT e $ERR).
saiu_com() { [ "$COD" -eq "$1" ]; }
out_tem()  { grep -qF -- "$1" "$OUT"; }
err_tem()  { grep -qF -- "$1" "$ERR"; }
err_nao_tem() { ! grep -qF -- "$1" "$ERR"; }

# O recorte mínimo do `update.sh` que o script avalia: sem consulta a banco, 1 regra
# declarada e nenhuma faltando. O que vem depois do recorte NÃO pode ser executado.
stub_update() {  # stub_update <arquivo>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
  # E AS REGRAS DE ISOLAMENTO SÃO CONFERIDAS (stub do teste)
  if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}${AUDIT_API_KEY:-}" ]; then
    printf 'credencial exposta\n' > "$CREDENTIAL_LEAK_FILE"
  fi
  esperadas="$(awk 'BEGIN { print "politica_a|tabela_a" }')"
  faltando="$(printf '')"
  echo "depois do recorte: o script nunca executa isto" >&2; exit 97
EOF
}

# ── O upstream: v1.63.0 e v1.64.0, cada uma com o seu update.sh ──────────────
UP="$WORK/upstream"
git init -q "$UP"
(
  cd "$UP"
  stub_update hostgator-setup-kit/update.sh
  git add -A; git commit -q -m "v1.63.0"; git tag v1.63.0
  echo "# 1.64" >> hostgator-setup-kit/update.sh
  git commit -q -am "v1.64.0"; git tag v1.64.0
)
# Um upstream que só tem a v1.64.0 (a v1.63.0 — a fixa do script — não existe nele).
UP_SEM_163="$WORK/upstream-sem-1.63"
git init -q "$UP_SEM_163"
(
  cd "$UP_SEM_163"
  stub_update hostgator-setup-kit/update.sh
  git add -A; git commit -q -m "v1.64.0"; git tag v1.64.0
)
printf '{"url":"x","tag_name":"v1.64.0","draft":false}\n' > "$WORK/latest-1.64.json"

# ── A cópia do projeto (script REAL + kit REAL) com origin SEM tags ─────────
montar_fork() {  # montar_fork — imprime o diretório de um fork novo (cada caso usa o seu)
  # `mktemp` e não um contador: a função roda em `$(...)`, e o contador não sobe no pai.
  local d
  d="$(mktemp -d "$WORK/fork.XXXXXX")"
  mkdir -p "$d/scripts" "$d/hostgator-setup-kit"
  cp "$RAIZ/scripts/conferir-isolamento-do-kit.sh" "$d/scripts/"
  # `_common.sh` carrega o irmão `_i18n.sh` — sem ele a função de release não existe.
  cp "$RAIZ/hostgator-setup-kit/_common.sh" "$RAIZ/hostgator-setup-kit/_i18n.sh" "$d/hostgator-setup-kit/"
  stub_update "$d/hostgator-setup-kit/update.sh"
  {
    git init -q "$d"
    git init -q --bare "$d.origin.git"
    ( cd "$d" && git add -A && git commit -q -m fork && git remote add origin "$d.origin.git" )
  } >/dev/null 2>&1
  printf '%s' "$d"
}

rodar() {  # rodar <dir> [VAR=valor...] — roda o script do dir; deixa $COD, $OUT, $ERR
  local d="$1"; shift
  OUT="$WORK/out"; ERR="$WORK/err"; : > "$OUT"; : > "$ERR"
  ( cd "$d" && env "$@" bash scripts/conferir-isolamento-do-kit.sh container-fake banco-fake >"$OUT" 2>"$ERR" )
  COD=$?
}

echo '── 1. Fork sem release e sem tag, upstream com release: conferência RODA e passa'
F="$(montar_fork)"
rodar "$F" CONFERENCIA_KIT_UPSTREAM_GIT="$UP" CONFERENCIA_KIT_UPSTREAM_API="file://$WORK/latest-1.64.json"
check "sai com 0" saiu_com 0
check "confere o update.sh deste checkout" out_tem "✓ update.sh deste checkout"
check "confere o update.sh da última release DO UPSTREAM (v1.64.0)" out_tem "✓ update.sh da última release (v1.64.0)"
check "confere a v1.63.0 buscada no upstream" out_tem "✓ update.sh da v1.63.0 (sem filtro por tabela)"
check "avisa no stderr que usou o upstream (nunca em silêncio)" err_tem "aviso: o origin não tem release publicada"
check "não aparece FATAL" err_nao_tem "FATAL"

echo '── 2. Sem resposta de NENHUMA fonte: REPROVA (o fallback acrescenta fonte, não afrouxa)'
F="$(montar_fork)"
rodar "$F" CONFERENCIA_KIT_UPSTREAM_GIT="$UP" CONFERENCIA_KIT_UPSTREAM_API="file://$WORK/nao-existe.json"
check "sai com 1" saiu_com 1
check "diz que não soube a última release" err_tem "FATAL: não consegui saber qual é a última release publicada"
check "ensina o botão manual" err_tem "CONFERENCIA_KIT_RELEASE=vX.Y.Z"
check "não confere nada em silêncio (nenhuma linha de sucesso)" bash -c '! grep -q "✓" "$0"' "$OUT"

echo '── 3. Origin COM release própria: o origin vence, o upstream não é consultado para ela'
F="$(montar_fork)"
( cd "$F" && git tag v2.0.0 )   # a release do fork: tag local → `ultima_release_estavel` a acha
rodar "$F" CONFERENCIA_KIT_UPSTREAM_GIT="$UP" CONFERENCIA_KIT_UPSTREAM_API="file://$WORK/nao-existe.json"
check "sai com 0 (a API do upstream, que não existe, nem foi precisada)" saiu_com 0
check "confere a release do PRÓPRIO fork (v2.0.0)" out_tem "✓ update.sh da última release (v2.0.0)"
check "a v1.63.0, que o fork não tem, vem do upstream" out_tem "✓ update.sh da v1.63.0 (sem filtro por tabela)"
check "sem aviso de upstream para a release" err_nao_tem "aviso: o origin não tem release publicada"

echo '── 4. Tag que não existe em fonte nenhuma: reprova DIZENDO qual'
F="$(montar_fork)"
rodar "$F" CONFERENCIA_KIT_RELEASE=v9.9.9 CONFERENCIA_KIT_UPSTREAM_GIT="$UP"
check "sai com 1" saiu_com 1
check "nomeia a tag ausente" err_tem "FATAL: a tag v9.9.9 não existe no origin nem no upstream"

echo '── 5. Falha transitória ao consultar origin: NÃO mascara consultando upstream'
F="$(montar_fork)"
mkdir -p "$WORK/git-shim"
REAL_GIT="$(command -v git)"
cat > "$WORK/git-shim/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"ls-remote --tags origin"*) echo origin-query-failed >> "\$GIT_SHIM_LOG"; exit 128 ;;
  *"ls-remote --tags"*) echo upstream-query-unexpected >> "\$GIT_SHIM_LOG" ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/git-shim/git"
GIT_SHIM_LOG="$WORK/git-shim.log"; export GIT_SHIM_LOG; : > "$GIT_SHIM_LOG"
rodar "$F" PATH="$WORK/git-shim:$PATH" CONFERENCIA_KIT_UPSTREAM_GIT="$UP" CONFERENCIA_KIT_UPSTREAM_API="file://$WORK/latest-1.64.json"
check "sai com 1" saiu_com 1
check "identifica falha ao consultar origin" err_tem "não consegui consultar as tags do origin"
check "não tenta upstream após erro transitório do origin" bash -c '! grep -q upstream-query-unexpected "$1"' _ "$GIT_SHIM_LOG"

echo '── 6. Falha transitória no upstream: distingue erro de tag ausente'
F="$(montar_fork)"
cat > "$WORK/git-shim/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"ls-remote --tags origin"*) exec "$REAL_GIT" "\$@" ;;
  *"ls-remote --tags"*) echo upstream-query-failed >> "\$GIT_SHIM_LOG"; exit 128 ;;
  *fetch*) echo unexpected-fetch >> "\$GIT_SHIM_LOG"; exit 128 ;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/git-shim/git"
GIT_SHIM_LOG="$WORK/upstream-shim.log"; export GIT_SHIM_LOG; : > "$GIT_SHIM_LOG"
rodar "$F" PATH="$WORK/git-shim:$PATH" CONFERENCIA_KIT_UPSTREAM_GIT="$UP"
check "sai com 1" saiu_com 1
check "explica a falha de consulta no upstream" err_tem "falha ao consultar tags do upstream"
check "não chama fetch após erro de consulta" bash -c '! grep -q unexpected-fetch "$1"' _ "$GIT_SHIM_LOG"

echo '── 7. Upstream sem a v1.63.0 fixa: a conferência dela REPROVA, não é pulada'
F="$(montar_fork)"
rodar "$F" CONFERENCIA_KIT_UPSTREAM_GIT="$UP_SEM_163" CONFERENCIA_KIT_UPSTREAM_API="file://$WORK/latest-1.64.json"
check "sai com 1" saiu_com 1
check "nomeia a v1.63.0 ausente" err_tem "FATAL: a tag v1.63.0 não existe no origin nem no upstream"
check "a release que existe foi conferida mesmo assim" out_tem "✓ update.sh da última release (v1.64.0)"

echo '── 6. O caminho do CI (GH_TOKEN + gh): pergunta ao upstream pelo slug certo'
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Dublê do gh: o repositório do origin não tem release (sai 1); o -R <slug> tem a v1.64.0.
echo "$*" >> "$GH_LOG"
case "$*" in
  *"-R "*) printf 'v1.64.0\n' ;;
  *) echo "release not found" >&2; exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/gh"
F="$(montar_fork)"
GH_LOG="$WORK/gh.log"; : > "$GH_LOG"
CREDENTIAL_LEAK_FILE="$WORK/credential-leak"; rm -f "$CREDENTIAL_LEAK_FILE"
rodar "$F" PATH="$WORK/bin:$PATH" GH_LOG="$GH_LOG" CREDENTIAL_LEAK_FILE="$CREDENTIAL_LEAK_FILE" GH_TOKEN=x GITHUB_TOKEN=y AUDIT_API_KEY=z CONFERENCIA_KIT_UPSTREAM_GIT="$UP"
check "sai com 0" saiu_com 0
check "perguntou primeiro ao origin (sem -R)" grep -qE '^release view --json tagName -q \.tagName$' "$GH_LOG"
check "depois ao upstream padrão, pelo slug" grep -qF -- "release view -R melgarafael/DeskcommCRM --json tagName -q .tagName" "$GH_LOG"
check "confere a release que o gh devolveu (v1.64.0)" out_tem "✓ update.sh da última release (v1.64.0)"
check "avisa que usou o upstream" err_tem "aviso: o origin não tem release publicada"
check "o trecho avaliado não recebeu tokens nem outra chave de API" bash -c '[ ! -e "$1" ]' _ "$CREDENTIAL_LEAK_FILE"

echo
if [ "$FAILS" -eq 0 ]; then echo "OK — a conferência do kit não depende de release no origin"; else echo "FALHOU: $FAILS"; exit 1; fi
