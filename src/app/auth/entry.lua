local cjson = require "cjson"
local http = require "resty.http"

-- private reject function (closes conn)
local function reject(status, message)
    ngx.status = status
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode({
        error = message
    }))
    return ngx.exit(status)
end

local function read_body()
    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if body then
        return body
    end

    local body_file = ngx.req.get_body_file()
    if not body_file then
        return "" -- no body because service domain doesnt close conn by itself in a domain
    end

    local file = io.open(body_file, "rb")
    if not file then
        return ""
    end

    body = file:read("*a") or ""
    file:close()
    
    return body
end

