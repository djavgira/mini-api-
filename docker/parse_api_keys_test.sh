#!/bin/sh
# Verifies that api_keys extraction ignores provider api keys and prefers the
# administrative role. Run from the repository root.
set -eu
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT HUP INT TERM
cat > "$dir/config.yaml" <<'YAML'
providers:
  - provider: openai
    api: sk-provider-not-a-client-key
    model:
      - gpt-4o
api_keys:
  - api: sk-first
    model:
      - all
  - api: sk-admin
    role: admin
    model:
      - gpt-4o
  - api: "sk-quoted"
    role: admin-ops
preferences:
  api_keys:
    - api: sk-decoy
YAML
got=$(sh docker/parse-api-keys.awk "$dir/config.yaml" | tr '\t' ':')
want='sk-first:
sk-admin:admin
sk-quoted:admin-ops'
if [ "$got" != "$want" ]; then
    echo "api key extraction mismatch" >&2
    printf 'got:\n%s\nwant:\n%s\n' "$got" "$want" >&2
    exit 1
fi
