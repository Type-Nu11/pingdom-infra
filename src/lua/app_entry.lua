local cjson = require "cjson"
local request = require "lua.request"
local validator = require "lua.rust.validator"
local response = require "lua.response"


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