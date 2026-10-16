#!/usr/bin/env bash
# test-db-sem-docker.sh — roda os testes de banco (`pnpm test:db` e `pnpm test:db:update`)
# numa máquina SEM Docker, contra um PostgreSQL 16 local de binários oficiais.
#
#   bash scripts/test-db-sem-docker.sh preparar            # monta o PostgreSQL local (uma vez; ~2 min; precisa de rede)
#   bash scripts/test-db-sem-docker.sh test:db [args…]     # = pnpm test:db [args…], com o dublê de `docker` no PATH
#   bash scripts/test-db-sem-docker.sh test:db:update      # = pnpm test:db:update
#   bash scripts/test-db-sem-docker.sh limpar              # apaga tudo o que `preparar` baixou e montou
#
# ── Para quem serve ─────────────────────────────────────────────────────────
#
# Sandbox de agente, VM mínima, CI sem Docker: lugares onde `pnpm test:db` morria em
# `docker: command not found` e as 447 invariantes de banco ficavam SEM MEDIÇÃO. Quem
# tem Docker não precisa disto — `pnpm test:db` continua sendo o gate, e o que decide o
# check obrigatório `invariants` é o CI (pg15 e pg17, na imagem pgvector/pgvector).
#
# ── ⚠️ O QUE ISTO NÃO É ────────────────────────────────────────────────────
#
# NÃO é a imagem do CI, e verde aqui não substitui o `invariants`. As diferenças,
# medidas na montagem:
#   - PostgreSQL 16.14 (o CI roda 15 e 17). O piso do baseline é o 15; o 16 está entre os dois.
#   - SEM libxml: as funções XML do SQL (`query_to_xml`…) não existem. Só o invariante
#     harness-isola-por-arquivo usa (no `censo()`); ele reprova aqui sem defeito do produto.
#   - uuid-ossp SUBSTITUÍDO por uma extensão SQL (`uuid_generate_v4()` → `gen_random_uuid()`,
#     que é a única função de UUID que o baseline usa). pgvector, pgcrypto, citext e
#     pg_trgm são os REAIS (pgcrypto, citext e pg_trgm compilados da fonte oficial do
#     MESMO PostgreSQL; pgvector vem pronto no wheel).
#   - Collation C.UTF-8 (a imagem do CI usa en_US.utf8): ORDER BY de texto com acento ou
#     caixa mista pode divergir.
#   - fsync desligado (mais rápido; não muda semântica de SQL).
#
# ── De onde vem cada peça ───────────────────────────────────────────────────
#
#   binários do PostgreSQL + pgvector : wheel `pixeltable-pgserver` do PyPI, FIXADO por
#                                       versão E por SHA-256 (abaixo) — outro hash aborta.
#   fonte de pgcrypto/citext/pg_trgm  : codeload.github.com/postgres/postgres (tag da MESMA versão)
#   headers de OpenSSL e zlib         : codeload.github.com (só os .h; a lib é a do sistema)
# Tudo em `$DESKCOMM_SEM_DOCKER_DIR` (padrão: ${TMPDIR:-/tmp}/deskcomm-sem-docker), fora do repositório.
#
# ── O dublê de `docker` ─────────────────────────────────────────────────────
#
# Cobre só `run`, `port`, `exec` e `rm` — o que scripts/test-db.sh,
# scripts/test-update-com-dados.sh e os invariantes usam. "Container" = um cluster
# PostgreSQL descartável (initdb + pg_ctl), apagado no `rm`. Subcomando fora disso
# sai com 125 e diz qual.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${DESKCOMM_SEM_DOCKER_DIR:-${TMPDIR:-/tmp}/deskcomm-sem-docker}"

WHEEL_REQ="pixeltable-pgserver==0.6.0"
WHEEL_SHA256="620f397b925a6a6ea39544084d3d86e3775acf41db6a56f8f3b800488bd33c6d"
ZLIB_TAG="v1.3.1"

falta() { echo "ERRO: $*" >&2; exit 1; }

# Nunca execute arquivos de uma árvore em /tmp que possa ter sido plantada ou
# alterada por outro usuário. Rejeita symlinks, dono inesperado e permissões de
# escrita de grupo/outros antes de ler o marcador ou antepor bin/ ao PATH.
validar_base_segura() {
  local canon pai uid dono modo
  uid="$(id -u)"
  [ ! -L "$BASE" ] || falta "diretório de dados é symlink: $BASE"
  canon="$(realpath -m -- "$BASE")" || falta "não consegui canonicalizar $BASE"
  [ "$canon" = "$BASE" ] || falta "use um caminho canônico (sem symlink nos diretórios pais): $BASE"
  pai="$(dirname "$BASE")"
  [ -d "$pai" ] || falta "diretório pai inexistente: $pai"
  [ ! -L "$pai" ] || falta "diretório pai é symlink: $pai"
  dono="$(stat -c %u -- "$pai")"; modo="$(stat -c %a -- "$pai")"
  [ "$dono" = "$uid" ] || [ "$dono" = 0 ] || falta "diretório pai pertence a outro usuário: $pai"
  # Diretórios globais como /tmp são permitidos apenas com sticky bit.
  if (( (8#$modo & 8#0022) != 0 )) && (( (8#$modo & 8#1000) == 0 )); then
    falta "diretório pai permite escrita por terceiros sem sticky bit: $pai"
  fi
  [ -e "$BASE" ] || return 0
  [ -d "$BASE" ] || falta "caminho de dados não é diretório: $BASE"
  dono="$(stat -c %u -- "$BASE")"; modo="$(stat -c %a -- "$BASE")"
  [ "$dono" = "$uid" ] || falta "diretório de dados pertence a outro usuário: $BASE"
  (( (8#$modo & 8#0022) == 0 )) || falta "diretório de dados permite escrita por grupo/outros: $BASE"
  for pai in "$BASE/bin" "$BASE/bin/docker" "$BASE/.pronto"; do
    [ ! -L "$pai" ] || falta "arquivo de preparação é symlink: $pai"
    [ ! -e "$pai" ] && continue
    dono="$(stat -c %u -- "$pai")"; modo="$(stat -c %a -- "$pai")"
    [ "$dono" = "$uid" ] || falta "arquivo de preparação pertence a outro usuário: $pai"
    (( (8#$modo & 8#0022) == 0 )) || falta "arquivo permite escrita por grupo/outros: $pai"
  done
}

escrever_duble_de_docker() {  # escrever_duble_de_docker — grava $BASE/bin/docker
  cat > "$BASE/bin/docker" <<EOF
#!/usr/bin/env bash
# Dublê MÍNIMO do \`docker\` (gerado por scripts/test-db-sem-docker.sh — não edite).
set -euo pipefail
export LD_LIBRARY_PATH="$BASE/libs\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PATH="$BASE/pg/bin:\$PATH"
STATE="$BASE/state"
mkdir -p "\$STATE"
EOF
  cat >> "$BASE/bin/docker" <<'EOF'

porta_livre() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

cmd="${1:-}"; shift || true
case "$cmd" in
  run)
    name=""; pub=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -d|--detach|--rm|-i|-t|-it|--init) shift ;;
        --name) name="$2"; shift 2 ;;
        --name=*) name="${1#*=}"; shift ;;
        -p|--publish) pub="$2"; shift 2 ;;
        --label|-l|-e|--env|-v|--volume|--network|--net|--shm-size|--memory|-m|--user|-u|-w|--workdir|--entrypoint|--restart|--cpus|--tmpfs|--add-host|--platform)
          shift 2 ;;
        -*) shift ;;
        *) break ;;
      esac
    done
    shift   # a imagem; o que sobra são argumentos do servidor (-c chave=valor)
    [ -n "$name" ] || name="semdocker-$$"
    dir="$STATE/$name"; rm -rf "$dir"; mkdir -p "$dir/sock"
    # -p 127.0.0.1::5432 | 127.0.0.1:PORTA:5432 | PORTA:5432 | 5432
    IFS=: read -r -a partes <<<"$pub"
    hostport=""
    if [ "${#partes[@]}" -ge 3 ]; then hostport="${partes[1]}"; elif [ "${#partes[@]}" -eq 2 ]; then hostport="${partes[0]}"; fi
    [ -n "$hostport" ] || hostport="$(porta_livre)"
    echo "$hostport" > "$dir/port"
    initdb -D "$dir/data" -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >"$dir/initdb.log" 2>&1
    extra=""
    while [ $# -gt 0 ]; do extra="$extra $1"; shift; done
    pg_ctl -D "$dir/data" -l "$dir/postgres.log" -w \
      -o "-p $hostport -k $dir/sock -c listen_addresses=127.0.0.1 -c fsync=off -c synchronous_commit=off -c full_page_writes=off -c max_connections=200$extra" \
      start >"$dir/pg_ctl.log" 2>&1 || { cat "$dir/pg_ctl.log" "$dir/postgres.log" >&2; exit 125; }
    printf '%s\n' "$(printf '%s' "$name" | sha256sum | cut -c1-64)"
    ;;
  port)
    name="$1"
    [ -f "$STATE/$name/port" ] || { echo "Error: No such container: $name" >&2; exit 1; }
    echo "127.0.0.1:$(cat "$STATE/$name/port")"
    ;;
  exec)
    while [ $# -gt 0 ]; do
      case "$1" in
        -i|-t|-it|--interactive|--tty|--privileged|-d|--detach) shift ;;
        -e|--env) export "$2"; shift 2 ;;
        -u|--user|-w|--workdir) shift 2 ;;
        -*) shift ;;
        *) break ;;
      esac
    done
    name="$1"; shift
    [ -f "$STATE/$name/port" ] || { echo "Error response from daemon: No such container: $name" >&2; exit 1; }
    export PGHOST=127.0.0.1 PGPORT="$(cat "$STATE/$name/port")" PGUSER=postgres
    exec "$@"
    ;;
  rm)
    nomes=()
    for a in "$@"; do case "$a" in -*) ;; *) nomes+=("$a") ;; esac; done
    for name in "${nomes[@]}"; do
      dir="$STATE/$name"
      [ -d "$dir/data" ] && pg_ctl -D "$dir/data" -m immediate -w stop >/dev/null 2>&1 || true
      rm -rf "$dir"
      echo "$name"
    done
    ;;
  *)
    echo "docker (dublê do test-db-sem-docker.sh): subcomando não suportado: $cmd $*" >&2
    exit 125
    ;;
esac
EOF
  chmod +x "$BASE/bin/docker"
}

preparar() {
  validar_base_segura
  if [ -f "$BASE/.pronto" ]; then echo "já preparado em $BASE"; return 0; fi
  [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] || falta "só Linux x86_64 (o wheel é manylinux x86_64)"
  [ "$(id -u)" -ne 0 ] || falta "o PostgreSQL se recusa a rodar como root; rode como usuário comum"
  local c
  for c in python3 gcc make perl curl tar openssl sha256sum; do
    command -v "$c" >/dev/null 2>&1 || falta "falta o comando '$c'"
  done
  python3 -m pip --version >/dev/null 2>&1 || falta "falta o pip do python3"

  # Os headers de OpenSSL TÊM de ser da mesma série da libcrypto do sistema (o pgcrypto
  # é compilado contra eles e carregado contra a lib do sistema).
  local ossl
  ossl="$(openssl version | awk '{print $2}')"
  case "$ossl" in 3.0.*) ;; *) falta "OpenSSL do sistema é $ossl; este script só sabe a série 3.0.x" ;; esac

  rm -rf "$BASE"; mkdir -p "$BASE/wheel" "$BASE/src" "$BASE/bin" "$BASE/state"
  echo "==> 1/6 wheel do PostgreSQL ($WHEEL_REQ)"
  python3 -m pip download "$WHEEL_REQ" --no-deps --only-binary=:all: \
    --implementation cp --python-version 3.11 --abi cp311 \
    --platform manylinux_2_28_x86_64 --platform manylinux_2_27_x86_64 \
    -d "$BASE/wheel" >/dev/null
  local whl got
  whl="$(ls "$BASE"/wheel/*.whl | head -1)"
  got="$(sha256sum "$whl" | awk '{print $1}')"
  [ "$got" = "$WHEEL_SHA256" ] || falta "o wheel baixado tem outro SHA-256 ($got) — abortei sem executar nada dele"

  echo "==> 2/6 extraindo binários e bibliotecas"
  python3 - "$whl" "$BASE" <<'PY'
import os, sys, zipfile
whl, base = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(whl)
for info in z.infolist():
    n = info.filename
    if n.startswith("pixeltable_pgserver/pginstall/"):
        destino = os.path.join(base, "pg", n[len("pixeltable_pgserver/pginstall/"):])
    elif n.startswith("pixeltable_pgserver.libs/"):
        destino = os.path.join(base, "libs", n[len("pixeltable_pgserver.libs/"):])
    else:
        continue
    if info.is_dir():
        os.makedirs(destino, exist_ok=True)
        continue
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with z.open(info) as src, open(destino, "wb") as dst:
        dst.write(src.read())
    modo = (info.external_attr >> 16) & 0o777
    os.chmod(destino, modo or 0o644)
PY
  export LD_LIBRARY_PATH="$BASE/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  local pgver tag pgc
  pgc="$BASE/pg/bin/pg_config"
  pgver="$("$BASE/pg/bin/postgres" --version | awk '{print $3}')"   # ex.: 16.14
  tag="REL_${pgver//./_}"
  echo "    PostgreSQL $pgver (fonte: $tag)"

  echo "==> 3/6 fonte oficial do PostgreSQL (só contrib: pgcrypto, citext, pg_trgm)"
  curl -fsSL --max-time 300 -o "$BASE/src/pg.tgz" "https://codeload.github.com/postgres/postgres/tar.gz/refs/tags/$tag"
  tar -xzf "$BASE/src/pg.tgz" -C "$BASE/src" --wildcards '*/contrib/pgcrypto/*' '*/contrib/citext/*' '*/contrib/pg_trgm/*'
  local contrib
  contrib="$(ls -d "$BASE"/src/postgres-*/contrib | head -1)"

  echo "==> 4/6 headers de OpenSSL $ossl e zlib (a biblioteca é a do sistema)"
  curl -fsSL --max-time 300 -o "$BASE/src/openssl.tgz" "https://codeload.github.com/openssl/openssl/tar.gz/refs/tags/openssl-$ossl"
  tar -xzf "$BASE/src/openssl.tgz" -C "$BASE/src"
  ( cd "$BASE"/src/openssl-openssl-"$ossl" \
    && perl ./Configure linux-x86_64 no-asm no-shared no-tests >"$BASE/src/openssl-configure.log" 2>&1 \
    && make build_generated >"$BASE/src/openssl-generated.log" 2>&1 ) || falta "não consegui gerar os headers do OpenSSL (log: $BASE/src/openssl-*.log)"
  curl -fsSL --max-time 120 -o "$BASE/src/zlib.tgz" "https://codeload.github.com/madler/zlib/tar.gz/refs/tags/$ZLIB_TAG"
  tar -xzf "$BASE/src/zlib.tgz" -C "$BASE/src"
  ( cd "$BASE/src/zlib-${ZLIB_TAG#v}" && ./configure >"$BASE/src/zlib-configure.log" 2>&1 ) || falta "zlib: configure falhou"
  mkdir -p "$BASE/src/lib"
  ln -sf "$(ls /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /lib/x86_64-linux-gnu/libcrypto.so.3 2>/dev/null | head -1)" "$BASE/src/lib/libcrypto.so"
  ln -sf "$(ls /lib/x86_64-linux-gnu/libz.so.1 /usr/lib/x86_64-linux-gnu/libz.so.1 2>/dev/null | head -1)" "$BASE/src/lib/libz.so"

  echo "==> 5/6 compilando e instalando citext, pg_trgm e pgcrypto"
  local m inc
  inc="-I$BASE/src/openssl-openssl-$ossl/include -I$BASE/src/zlib-${ZLIB_TAG#v}"
  for m in citext pg_trgm pgcrypto; do
    ( cd "$contrib/$m" \
      && make USE_PGXS=1 PG_CONFIG="$pgc" PG_CPPFLAGS="$inc" SHLIB_LINK="-L$BASE/src/lib -lcrypto -lz" >"$BASE/src/build-$m.log" 2>&1 \
      && make USE_PGXS=1 PG_CONFIG="$pgc" PG_CPPFLAGS="$inc" SHLIB_LINK="-L$BASE/src/lib -lcrypto -lz" install >>"$BASE/src/build-$m.log" 2>&1 ) \
      || falta "falhou compilar $m (log: $BASE/src/build-$m.log)"
  done

  echo "==> 6/6 uuid-ossp substituto e dublê de docker"
  local ext
  ext="$("$pgc" --sharedir)/extension"
  cat > "$ext/uuid-ossp.control" <<'EOF'
comment = 'SUBSTITUTO de teste do uuid-ossp (sem libuuid): uuid_generate_v4 via gen_random_uuid'
default_version = '1.1'
relocatable = true
EOF
  cat > "$ext/uuid-ossp--1.1.sql" <<'EOF'
-- SUBSTITUTO de teste: este PostgreSQL não foi compilado com libuuid. O baseline do projeto
-- usa só uuid_generate_v4(); aqui ela é gen_random_uuid() (PostgreSQL 13+).
CREATE FUNCTION uuid_nil() RETURNS uuid
  AS $$ SELECT '00000000-0000-0000-0000-000000000000'::uuid $$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION uuid_generate_v4() RETURNS uuid
  AS $$ SELECT gen_random_uuid() $$ LANGUAGE sql VOLATILE STRICT PARALLEL SAFE;
EOF
  escrever_duble_de_docker
  touch "$BASE/.pronto"
  echo "pronto em $BASE — agora: bash scripts/test-db-sem-docker.sh test:db"
}

rodar() {  # rodar <script do package.json> [args…]
  validar_base_segura
  [ -f "$BASE/.pronto" ] || falta "ainda não preparado — rode primeiro: bash scripts/test-db-sem-docker.sh preparar"
  command -v pnpm >/dev/null 2>&1 || falta "falta o pnpm (corepack enable)"
  echo "==> sem Docker: PostgreSQL local de $BASE (NÃO é a imagem do CI — leia o cabeçalho deste script)" >&2
  cd "$ROOT"
  PATH="$BASE/bin:$PATH" exec pnpm "$@"
}

case "${1:-}" in
  preparar) preparar ;;
  test:db|test:db:update) rodar "$@" ;;
  limpar)
    validar_base_segura
    for d in "$BASE"/state/*/; do
      [ -d "$d/data" ] && "$BASE/pg/bin/pg_ctl" -D "$d/data" -m immediate -w stop >/dev/null 2>&1 || true
    done
    rm -rf "$BASE"; echo "removido: $BASE" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
