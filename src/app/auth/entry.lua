local cjson = require "cjson"
local request = require "app.auth.request"
local validator = require "app.rust.validator"

-- private reject function (closes conn)
local function reject(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = message
    }))
    return ngx.exit(status)
end

local req, err = request.build()

if not req then
    return reject(ngx.HTTP_BAD_REQUEST, err)
end

local ok, validation_error = validator.validate(req)

if not ok then
    return reject(
        validation_error.status or ngx.HTTP_UNAUTHORIZED,
        validation_error.message or "request rejected"
    )
end