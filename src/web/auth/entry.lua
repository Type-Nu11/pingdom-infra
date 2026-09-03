local cjson = require "cjson"

local function reject(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = message
    }))
    return ngx.exit(status)
end


local _M = {}

function _M.collect()
    local ip = ngx.var.remote_addr or ""
    local method = ngx.req.get_method() or ""
    local uri = ngx.var.request_uri or ""
    local ua = ngx.var.http_user_agent or ""

    local result = {
        ip = ip,
        method = method,
        uri = uri,
        user_agent = ua
    }

    for _, val in ipairs(result) do
        if not val or val == "" then
            return reject(ngx.HTTP_BAD_REQUEST, "missing required request information")
        end
    end

    return result
end

return _M