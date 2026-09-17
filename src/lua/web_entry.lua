local request = require("lua.web_request")
local response = require("lua.common.response")
local jwt = require("lua.rust.web_validator")
local guard = require("lua.zig.guard")
local mysterio = require("lua.mysterio")

local req, err = request.build()
if not req then
    return response.reject(ngx.HTTP_BAD_REQUEST, err)
end

local token = req.token
if not token then
    return response.reject(
        ngx.HTTP_UNAUTHORIZED,
        "missing authentication token"
    )
end

local ok, claims_or_error = jwt.verify(token)
if not ok then
    return response.reject(
        claims_or_error.status or ngx.HTTP_UNAUTHORIZED,
        claims_or_error.message or tostring(claims_or_error)
    )
end

if guard.inspect then
    local guard_ok, guard_error = guard.inspect(req)

    if not guard_ok then
        -- return response.reject(
        --     guard_error.status or ngx.HTTP_FORBIDDEN,
        --     guard_error.message or "request blocked"
        -- )

        return mysterio.isolate(
            guard_error.message or "request isolated"
        )
    end
end

