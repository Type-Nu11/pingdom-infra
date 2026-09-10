local cjson = require("cjson.safe")

local _M = {}

function _M.reject(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = message
    }))
    return ngx.exit(status)
end

function _M.json(status, payload)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(payload))
    return ngx.exit(status)
end

return _M