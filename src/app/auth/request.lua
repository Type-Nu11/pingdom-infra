local _M = {}

local REQUIRED_HEADERS = {
    "x-timestamp",
    "x-signaturebase64",
    "x-app-version",
    "x-device-id"
}

local function read_body()
    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if body then
        return body
    end

    local body_file = ngx.req.get_body_file()
    if not body_file then
        return ""
    end

    local file = io.open(body_file, "rb")
    if not file then
        return ""
    end

    body = file:read("*a") or ""
    file:close()

    return body
end

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
        body = read_body(),
        timestamp = headers["x-timestamp"],
        signature = headers["x-signaturebase64"],
        app_version = headers["x-app-version"],
        device_id = headers["x-device-id"]
    }
end

return _M