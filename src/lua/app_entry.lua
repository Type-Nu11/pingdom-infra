-- Preflight has no JWT or app metadata; delegate CORS validation to the backend.
if ngx.req.get_method() == "OPTIONS" then
    return
end

local app_auth = require("lua.app_auth")
local response = require("lua.common.response")

local ok, status, message = app_auth.validate()
if not ok then
    return response.reject(status, message)
end
