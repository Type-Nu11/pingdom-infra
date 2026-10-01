local _M = {}
local jwt = require("lua.common.jwt")

local REQUIRED_HEADERS = {
    { name = "x-timestamp", display = "X-Timestamp", max_length = 20 },
    { name = "x-app-version", display = "X-App-Version", max_length = 64 },
    { name = "x-device-id", display = "X-Device-Id", max_length = 36 }
}

function _M.build()
    local headers = ngx.req.get_headers()
    local values = {}

    for _, header in ipairs(REQUIRED_HEADERS) do
        local value = headers[header.name]

        if value == nil or value == "" then
            return nil, "missing required header: " .. header.display
        end
        if type(value) ~= "string" then
            return nil, "header must be provided once: " .. header.display
        end
        if #value > header.max_length then
            return nil, "header is too long: " .. header.display
        end

        values[header.name] = value
    end

    return {
        timestamp = values["x-timestamp"],
        app_version = values["x-app-version"],
        device_id = values["x-device-id"],
        token = jwt.get_bearer_token(headers)
    }
end

return _M
