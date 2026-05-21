-- anti-crawling

local _M = {}

function _M.run()
    local ua = ngx.var.http_user_agent
    local ua_lower = ua:lower()

return _M