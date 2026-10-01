local native = require("lua.rust.native")

local _M = {}

function _M.validate(request)
    local minimum_version = os.getenv("APP_MIN_VERSION")
    if not minimum_version or minimum_version == "" then
        minimum_version = "0.0.0"
    end
    local result = native.validate_app_headers(
        request.timestamp, #request.timestamp,
        request.app_version, #request.app_version,
        minimum_version, #minimum_version,
        request.device_id, #request.device_id
    )

    if result ~= 0 then
        return false, {
            status = (result == 5 or result == 6) and 500 or 400,
            message = ({
                [1] = "invalid or stale X-Timestamp",
                [2] = "unsupported or invalid X-App-Version",
                [3] = "invalid X-Device-Id",
                [4] = "invalid app request headers",
                [5] = "system clock is unavailable",
                [6] = "invalid APP_MIN_VERSION configuration"
            })[result] or "invalid app request headers"
        }
    end

    return true
end

return _M
