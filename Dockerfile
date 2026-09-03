FROM rust:1.85-bookworm AS rust-builder

WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY rust ./rust

RUN cargo build --release


FROM openresty/openresty:alpine

RUN mkdir -p /etc/nginx/configs /src /usr/local/lib /var/log/nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY configs /etc/nginx/configs
COPY src /src
COPY --from=rust-builder /build/target/release/libapp_validator.so \
    /usr/local/lib/libapp_validator.so

EXPOSE 8081

CMD ["openresty", "-g", "daemon off;", "-c", "/etc/nginx/nginx.conf"]