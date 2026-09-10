local body = require("lua.common.body")
local jwt = require("lua.common.jwt")

local _M = {}

function _M.build()
    local headers = ngx.req.get_headers()

    return {
        method = ngx.req.get_method() or "",
        uri = ngx.var.request_uri or "",
        remote_addr = ngx.var.remote_addr or "",
        host = ngx.var.host or "",
        user_agent = headers["user-agent"] or "",
        authorization = headers["authorization"],
        token = jwt.get_bearer_token(headers),
        body = body.read_body()
    }
end

return _M