local native = require("lua.rust.native")

local _M = {}

function _M.validate(request)
    local secret = os.getenv("HMAC_SECRET_KEY") or ""
    if not secret or secret == "" then
        return false, {
            status = 500,
            message = "HMAC secret is not configured"
        }
    end

    local result = native.validate_app_request(
        request.method, #request.method,
        request.uri, #request.uri,
        request.timestamp, #request.timestamp,
        request.signature, #request.signature,
        request.app_version, #request.app_version,
        request.device_id, #request.device_id,
        request.body, #request.body,
        secret, #secret
    )

    if result ~= 0 then
        return false, {
            status = 401,
            message = "invalid app request"
        }
    end

    return true
end

return _M