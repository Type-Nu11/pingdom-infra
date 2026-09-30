-- JWT-only rollout: Spring remains responsible for authentication on app routes.
-- Only an explicit false disables HMAC; unset or invalid values fail closed.
if os.getenv("APP_HMAC_ENFORCE") == "false" then
    return
end

local request = require "lua.app_request"
local validator = require "lua.rust.app_validator"
local response = require "lua.common.response"


local req, err = request.build()

if not req then
    return response.reject(ngx.HTTP_BAD_REQUEST, err)
end

local ok, validation_error = validator.validate(req)

if not ok then
    return response.reject(
        validation_error.status or ngx.HTTP_UNAUTHORIZED,
        validation_error.message or "request rejected"
    )
end
