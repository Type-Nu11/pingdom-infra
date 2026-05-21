FROM openresty/openresty:alpine AS builder

RUN apk add --no-cache perl curl