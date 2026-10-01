local request = require("lua.app_request")
local header_validator = require("lua.rust.app_validator")
local jwt_validator = require("lua.rust.web_validator")

local _M = {}

function _M.validate(require_jwt)
    local req, err = request.build()
    if not req then
        return false, 400, err
    end

    if require_jwt ~= false then
        if not req.token then
            return false, 401, "missing or invalid authentication token"
        end

        local jwt_ok, jwt_error = jwt_validator.verify(req.token)
        if not jwt_ok then
            return false,
                (jwt_error and jwt_error.status) or 401,
                (jwt_error and jwt_error.message) or "invalid JWT"
        end
    end

    local headers_ok, header_error = header_validator.validate(req)
    if not headers_ok then
        return false,
            (header_error and header_error.status) or 400,
            (header_error and header_error.message) or "invalid app request headers"
    end

    -- The legacy request signature is not part of the app contract anymore.
    ngx.req.clear_header("X-SignatureBase64")

    return true, req
end

return _M
