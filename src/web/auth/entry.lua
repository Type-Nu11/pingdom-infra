local guard = require "guard"

local ngx = ngx
local result = guard.collect(ngx)

if not result then
    return "guard failed to collect result"
end

return true