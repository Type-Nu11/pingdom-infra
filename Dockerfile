FROM openresty/openresty:alpine

RUN apk add --no-cache curl build-base luarocks5.4
RUN /usr/bin/luarocks-5.4 install lua-dotenv

WORKDIR /usr/local/openresty/nginx

COPY configs/nginx.conf.template /usr/local/openresty/nginx/nginx.conf
COPY configs /usr/local/openresty/nginx/configs
COPY src /src
COPY database /database
COPY .env /usr/local/openresty/nginx/.env

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
