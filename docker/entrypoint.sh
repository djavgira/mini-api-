#!/bin/sh
set -eu

config_path="${UNI_API_CONFIG_PATH:-/home/api.yaml}"
if [ ! -f "$config_path" ] && [ -z "${CONFIG_URL:-}" ]; then
    cat >&2 <<EOF
uni-api configuration is missing: '$config_path' does not exist and CONFIG_URL is unset.
Mount a configuration file, for example:
    docker run -v "\$PWD/api.yaml:/home/api.yaml:ro" ...
EOF
    exit 1
fi

mkdir -p /data "${DATA_DIR:-/data}" 2>/dev/null || true
chown -R gateway:gateway /home/data /data 2>/dev/null || true

# Split the configured upstream URLs into nginx-safe parts. The stock nginx
# entrypoint only runs /docker-entrypoint.d when PID 1 is nginx itself, which
# is not the case here (supervisord is PID 1), so do it explicitly.
. /docker-entrypoint.d/15-upstreams.envsh

# The console observes the local gateway. Register it as a source on first boot
# using an administrative api key from the gateway config. BOOTSTRAP_SOURCES is
# only inserted when no source exists yet, so edits made in the console survive
# restarts. Set GATEWAY_ADMIN_KEY to skip the lookup or override the choice.
if [ -z "${BOOTSTRAP_SOURCES:-}" ] && [ -n "${CONTROL_MASTER_KEY:-}" ]; then
    source_key="${GATEWAY_ADMIN_KEY:-}"
    if [ -z "$source_key" ] && [ -f "$config_path" ]; then
        keys=$(sh /usr/local/bin/parse-api-keys.awk "$config_path" || true)
        # Prefer an explicitly administrative key; fall back to the first key.
        source_key=$(printf '%s\n' "$keys" | awk -F"$(printf '\t')" '
            $2 ~ /^admin/ && admin == "" { admin = $1 }
            first == "" && $1 != "" { first = $1 }
            END { print (admin != "" ? admin : first) }')
    fi
    if [ -n "$source_key" ]; then
        # JSON-escape the key without requiring python or jq in the image.
        escaped=$(printf '%s' "$source_key" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g')
        export BOOTSTRAP_SOURCES="[{\"id\":\"${SOURCE_ID:-primary}\",\"name\":\"Local gateway\",\"base\":\"${GATEWAY_UPSTREAM:-http://127.0.0.1:8001}\",\"key\":\"${escaped}\"}]"
    else
        echo "no gateway api key found in '$config_path'; the console will start without a source" >&2
    fi
fi

# Render the site template. Values come only from the upstream splitter so an
# arbitrary environment variable can never be injected into nginx config.
template_dir=/etc/nginx/templates
target=/etc/nginx/conf.d/default.conf
mkdir -p /etc/nginx/conf.d
rm -f /etc/nginx/conf.d/default.conf
for template in "$template_dir"/*.template; do
    [ -f "$template" ] || continue
    envsubst '${ANALYTICS_UPSTREAM_SCHEME} ${ANALYTICS_UPSTREAM_ADDRESS} ${ANALYTICS_UPSTREAM_PATH} ${GATEWAY_UPSTREAM_SCHEME} ${GATEWAY_UPSTREAM_ADDRESS}' \
        < "$template" > "$target"
done

if ! nginx -t; then
    echo "rendered nginx configuration is invalid; refusing to start" >&2
    exit 1
fi

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
