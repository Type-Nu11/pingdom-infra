-- This File is for collection IP address and other information like UA, OS, Browser, ETC.

local _M = {}

function _M.collect()
    local ip = ngx.var.remote_addr
    local ua = ngx.var.http_user_agent
    local os = ngx.var.http_sec_ch_ua_platform
    local browser = ngx.var.http_sec_ch_ua

    return {
        ip = ip,
        ua = ua,
        os = os,
        browser = browser
    }
end

return _M