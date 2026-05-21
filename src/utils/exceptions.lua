local cjson = _G.core.cjson

local _M = {}

-- status = 숫자, error_message = 문자열
function _M.customException(status, error_message)
    ngx.status = status
    local response = {
        error = ngx.status,
        message = error_message
    }
    ngx.say(cjson.encode(response))
    return ngx.exit(status)
end

return _M