local ffi = require "ffi"

ffi.cdef[[
int validate_app_request(
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t
);
]]

local native = ffi.load("/usr/local/lib/libapp_validator.so")

local _M = {}

local function pair(value)
    return value, #value
end

function _M.validate(request)
    local secret = os.getenv("HMAC_SECRET_KEY") or ""
    if not secret or secret == "" then
        return false, {
            status = 500,
            message = "HMAC secret is not configured"
        }
    end

    local result = native.validate_app_request(
        pair(request.method),
        pair(request.uri),
        pair(request.timestamp),
        pair(request.signature),
        pair(request.app_version),
        pair(request.device_id),
        pair(request.body),
        pair(secret)
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