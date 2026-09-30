local request = require("lua.app_request")
local validator = require("lua.rust.app_validator")
local response = require("lua.common.response")

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

local groq_key = os.getenv("AI_API_KEY")

if not groq_key or groq_key == "" then
    return response.reject(
        ngx.HTTP_INTERNAL_SERVER_ERROR,
        "Groq API key is not configured"
    )
end

ngx.req.set_header("Authorization", "Bearer " .. groq_key)
ngx.req.set_header("Content-Type", "application/json")