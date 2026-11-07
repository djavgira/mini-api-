# Probe the combined image: confirms that every public path lands on the
# component that owns it. Run after `docker compose up -d` or against any
# running container.
#
#   sh docker/smoke-test.sh http://127.0.0.1:8000
set -eu

base=${1:-http://127.0.0.1:8000}
key=${2:-}
fail=0

check() {
    label=$1
    want=$2
    path=$3
    auth=$4
    if [ -n "$auth" ]; then
        code=$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $auth" "$base$path")
    else
        code=$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' "$base$path")
    fi
    if [ "$code" = "$want" ]; then
        printf '  ok   %-28s %s -> %s\n' "$label" "$path" "$code"
    else
        printf '  FAIL %-28s %s -> %s (want %s)\n' "$label" "$path" "$code" "$want"
        fail=1
    fi
}

echo "probing $base"
check "nginx healthz" 200 /healthz ""
check "console SPA" 200 / ""
check "SPA deep link" 200 /channels ""
check "analysis service" 200 /analytics/healthz ""
check "gateway models" 200 /v1/models "${key:-}"
check "gateway rejects anonymous" 403 /v1/models ""

if [ "$fail" -ne 0 ]; then
    echo "some paths are routed to the wrong component" >&2
    exit 1
fi
echo "all paths routed correctly"
