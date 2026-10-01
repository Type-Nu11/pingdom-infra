FROM rust:1.85-bookworm AS rust-builder

WORKDIR /build

COPY Cargo.toml Cargo.lock ./
COPY rust ./rust

RUN cargo build --release


FROM alpine:3.20 AS zig-builder

RUN apk add --no-cache zig libc-dev

WORKDIR /build

COPY zig/guard ./zig/guard

RUN cd zig/guard && \
    zig build -Doptimize=ReleaseFast


FROM openresty/openresty:alpine

RUN apk add --no-cache gettext

WORKDIR /app

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY configs /etc/nginx/config-templates
COPY src /src
COPY docker-entrypoint.sh /usr/local/bin/render-nginx-config
RUN chmod +x /usr/local/bin/render-nginx-config

COPY --from=rust-builder \
    /build/target/release/libapp_validator.so \
    /usr/local/lib/libapp_validator.so

COPY --from=zig-builder \
    /build/zig/guard/zig-out/lib/libweb_guard.so \
    /usr/local/lib/libweb_guard.so

EXPOSE 8081

CMD ["/usr/local/bin/render-nginx-config"]
