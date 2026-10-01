#!/bin/sh
set -eu

: "${BACKEND_HOST:?BACKEND_HOST must be set}"
: "${BACKEND_PORT:?BACKEND_PORT must be set}"

case "$BACKEND_PORT" in
    ''|*[!0-9]*)
        echo "BACKEND_PORT must be a numeric port" >&2
        exit 1
        ;;
esac

# Only substitute the backend variables. Nginx variables such as $host and
# $remote_addr in the included configs must remain untouched.
envsubst '${BACKEND_HOST} ${BACKEND_PORT}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

find /etc/nginx/config-templates -type f -name '*.conf' | while IFS= read -r template; do
    relative_path=${template#/etc/nginx/config-templates/}
    output="/etc/nginx/configs/${relative_path}"
    mkdir -p "$(dirname "$output")"
    envsubst '${BACKEND_HOST} ${BACKEND_PORT}' < "$template" > "$output"
done

openresty -t -c /etc/nginx/nginx.conf
exec openresty -c /etc/nginx/nginx.conf -g 'daemon off;'
