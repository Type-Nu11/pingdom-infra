local _M = {}

function _M.get_bearer_token(headers)

    local authorization = headers["authorization"]
    if not authorization then
        return nil
    end

    -- parser
    return authorization:match("^Bearer%s+(.+)$")
end

return _M