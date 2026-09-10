local body = require("lua.common.body")

local _M = {}

local REQUIRED_HEADERS = {
    "x-timestamp",
    "x-signaturebase64",
    "x-app-version",
    "x-device-id"
}

function _M.build()
    local headers = ngx.req.get_headers()

    for _, header in ipairs(REQUIRED_HEADERS) do
        local value = headers[header]

        if not value or value == "" then
            return nil, "missing required header: " .. header
        end
    end

    return {
        method = ngx.req.get_method(),
        uri = ngx.var.request_uri or "",
        body = body.read_body(),
        timestamp = headers["x-timestamp"],
        signature = headers["x-signaturebase64"],
        app_version = headers["x-app-version"],
        device_id = headers["x-device-id"]
    }
end

return _M