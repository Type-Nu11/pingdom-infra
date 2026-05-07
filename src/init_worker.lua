require("resty.acme.autossl").init_worker()

-- 인증서 미리 로드 (배포 후 첫 요청 SSL 실패 방지)
ngx.timer.at(0, function()
    local autossl = require("resty.acme.autossl")
    local http = require "resty.http"  -- 이거 추가
    local domains = { "api.clash.kr" }
    for _, domain in ipairs(domains) do
        local certkey, err = autossl.get_certkey(domain, "rsa")
        if err then
            ngx.log(ngx.ERR, "[Warmup] failed to load cert for ", domain, ": ", err)
        else
            ngx.log(ngx.INFO, "[Warmup] cert loaded for ", domain)
        end
    end

    local httpc = http.new()
    httpc:set_timeout(5000)
    local res, err = httpc:request_uri("https://api.clash.kr/health", {
        ssl_verify = false
    })
    if err then
        ngx.log(ngx.ERR, "[Warmup] SSL handshake failed: ", err)
    else
        ngx.log(ngx.INFO, "[Warmup] SSL handshake done, status: ", res.status)
    end
end)