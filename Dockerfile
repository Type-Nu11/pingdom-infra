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

WORKDIR /app

COPY nginx.conf /etc/nginx/nginx.conf
COPY configs /etc/nginx/configs
COPY src /src

COPY --from=rust-builder \
    /build/target/release/libapp_validator.so \
    /usr/local/lib/libapp_validator.so

COPY --from=zig-builder \
    /build/zig/guard/zig-out/lib/libweb_guard.so \
    /usr/local/lib/libweb_guard.so

EXPOSE 8081

CMD ["openresty", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]