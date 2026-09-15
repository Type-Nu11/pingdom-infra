local native = require("lua.rust.native")

local _M = {}

function _M.verify(token)
    local secret = os.getenv("JWT_SECRET_KEY") or ""

    if secret == "" then
        return false, {
            status = 500,
            message = "JWT secret is not configured"
        }
    end

    local result = native.verify_jwt(
        token,
        #token,
        secret,
        #secret
    )

    if result ~= 0 then
        return false, {
            status = 401,
            message = "invalid JWT"
        }
    end

    return true
end

return _M