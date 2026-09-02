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


return _M