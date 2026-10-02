local app_auth = require("lua.app_auth")
local response = require("lua.common.response")

local ok, status, message = app_auth.validate(false)
if not ok then
    return response.reject(status, message)
end
