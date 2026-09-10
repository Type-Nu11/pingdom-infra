local request = require("lua.web_request")
local response = require("lua.common.response")
local jwt = require("lua.common.jwt")
local guard = require("lua.zig.guard")

local req, err = request.build()
if not req then
    response.reject(ngx.HTTP_BAD_REQUEST, err)
end

local token = req.token
if not token then
    return response.reject(
        ngx.HTTP_UNAUTHORIZED,
        "missing authentication token"
    )
end

local ok, claims_or_error = jwt.verify(token)