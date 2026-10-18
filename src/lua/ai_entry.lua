local app_auth = require("lua.app_auth")
local response = require("lua.common.response")

local ok, status, message = app_auth.validate()
if not ok then
    return response.reject(status, message)
end

local ai_key = os.getenv("AI_API_KEY")

if not ai_key or ai_key == "" then
    return response.reject(
        ngx.HTTP_INTERNAL_SERVER_ERROR,
        "AI API key is not configured"
    )
end

-- The client JWT is only for proxy authentication, not the AI provider.
ngx.req.clear_header("Authorization")
ngx.req.set_header("x-api-key", ai_key)
ngx.req.set_header("anthropic-version", "2023-06-01")
ngx.req.set_header("Content-Type", "application/json")
