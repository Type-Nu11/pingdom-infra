#!/bin/sh
set -eu

: "${BACKEND_HOST:?BACKEND_HOST must be set}"
: "${BACKEND_PORT:?BACKEND_PORT must be set}"
export MCP_HOST="${MCP_HOST:-$BACKEND_HOST}"
export MCP_PORT="${MCP_PORT:-8081}"
export CONSOLE_HOST="${CONSOLE_HOST:-$BACKEND_HOST}"
export CONSOLE_PORT="${CONSOLE_PORT:-8082}"
export PINGCHA_ENABLED="${PINGCHA_ENABLED:-false}"
case "$PINGCHA_ENABLED" in
    true|false) ;;
    *) echo "PINGCHA_ENABLED must be true or false" >&2; exit 1 ;;
esac

case "$BACKEND_PORT" in
    ''|*[!0-9]*)
        echo "BACKEND_PORT must be a numeric port" >&2
        exit 1
        ;;
esac

case "$CONSOLE_PORT" in
    ''|*[!0-9]*)
        echo "CONSOLE_PORT must be a numeric port" >&2
        exit 1
        ;;
esac

case "$MCP_PORT" in
    ''|*[!0-9]*)
        echo "MCP_PORT must be a numeric port" >&2
        exit 1
        ;;
esac

# Only substitute configured template variables. Nginx variables such as $host and
# $remote_addr in the included configs must remain untouched.
envsubst '${BACKEND_HOST} ${BACKEND_PORT} ${MCP_HOST} ${MCP_PORT} ${CONSOLE_HOST} ${CONSOLE_PORT} ${PINGCHA_ENABLED}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

find /etc/nginx/config-templates -type f -name '*.conf' | while IFS= read -r template; do
    relative_path=${template#/etc/nginx/config-templates/}
    output="/etc/nginx/configs/${relative_path}"
    mkdir -p "$(dirname "$output")"
    envsubst '${BACKEND_HOST} ${BACKEND_PORT} ${MCP_HOST} ${MCP_PORT} ${CONSOLE_HOST} ${CONSOLE_PORT} ${PINGCHA_ENABLED}' < "$template" > "$output"
done

openresty -t -c /etc/nginx/nginx.conf
exec openresty -c /etc/nginx/nginx.conf -g 'daemon off;'
