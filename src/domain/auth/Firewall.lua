local ipChecker = require("collecter")

local FireWall = {}
FireWall.__index = FireWall

function FireWall.new()
    local self = setmetatable({}, FireWall)
    return self
end

function FireWall:run()
    local ipInfo = ipChecker.collect()
    local ip = ipInfo.ip

    -- IP 체크 로직
    if self:isBlockedIP(ip) then
        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.say("Access Denied")
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

end


return FireWall
