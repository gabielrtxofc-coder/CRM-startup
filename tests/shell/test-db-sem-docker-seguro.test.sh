#!/usr/bin/env bash
# Regression: a planted docker executable in a foreign-writable data directory
# must be rejected before it can be reached through the runner's prepended PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BASE="$WORK/deskcomm-sem-docker"
mkdir -p "$BASE/bin"
chmod 0777 "$BASE"
MARKER="$WORK/docker-was-executed"
cat > "$BASE/bin/docker" <<EOF
#!/usr/bin/env bash
touch "$MARKER"
EOF
chmod 0755 "$BASE/bin/docker"
touch "$BASE/.pronto"

set +e
DESKCOMM_SEM_DOCKER_DIR="$BASE" bash "$ROOT/scripts/test-db-sem-docker.sh" test:db >"$WORK/out" 2>"$WORK/err"
status=$?
set -e
[ "$status" -ne 0 ] || { echo 'FALHOU: base insegura foi aceita' >&2; exit 1; }
grep -q 'permite escrita por grupo/outros' "$WORK/err" || { cat "$WORK/err" >&2; echo 'FALHOU: motivo da recusa ausente' >&2; exit 1; }
[ ! -e "$MARKER" ] || { echo 'FALHOU: docker plantado foi executado' >&2; exit 1; }

echo 'OK — base gravável por terceiros recusada antes de executar o docker plantado'
