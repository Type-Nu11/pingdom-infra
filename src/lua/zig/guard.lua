local ffi = require("ffi")

ffi.cdef[[
int inspect_web_request(
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    size_t
);
]]

local library_path = os.getenv("WEB_GUARD_LIB")

if not library_path or library_path == "" then
    error("WEB_GUARD_LIB is not configured")
end

local native = ffi.load(library_path)

local _M = {}

local errors = {
    [20] = "invalid method",
    [21] = "uri too long",
    [22] = "user-agent too long",
    [23] = "body too large",
    [24] = "invalid control character",
}

function _M.inspect(req)
    local result = native.inspect_web_request(
        req.method, #req.method,
        req.uri, #req.uri,
        req.user_agent, #req.user_agent,
        #req.body
    )

    if result ~= 0 then
        return false, {
            status = 403,
            message = errors[result] or "request blocked"
        }
    end

    return true
end

return _M