require("acme_file").init() -- ACME 초기화

_G.core = {}

-- 1. 라이브러리 모듈 로드
_G.core.http = require("resty.http")
_G.core.cjson = require("cjson.safe")
_G.core.redis = require("resty.redis")
_G.core.ffi = require("ffi")


local prefix = ngx.config.prefix() -- Nginx 설치 경로 (예: /usr/local/openresty/nginx/)

local maxminddb = require "resty.maxminddb"

-- 두 개의 DB를 프로파일 형태로 한 번에 초기화
local ok, err = maxminddb.init({
    country = "/database/GeoLite2-Country.mmdb",
    asn     = "/database/GeoLite2-ASN.mmdb"
})

if not ok then
    ngx.log(ngx.ERR, "GeoIP 초기화 실패: ", err)
else
    _G.maxmind = maxminddb -- 전역에 라이브러리 자체를 저장
    ngx.log(ngx.INFO, "GeoIP (Country & ASN) 로드 완료!")
end

-- 초기화 로그
ngx.log(ngx.INFO, " 라이브러리 초기화 완료")