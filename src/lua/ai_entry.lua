local app_auth = require("lua.app_auth")
local response = require("lua.common.response")

local ok, status, message = app_auth.validate()
if not ok then
    return response.reject(status, message)
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
