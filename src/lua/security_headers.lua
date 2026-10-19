local M = {}

function M.apply()
    -- Assignment replaces upstream duplicates and also covers local responses.
    ngx.header["X-Frame-Options"] = "SAMEORIGIN"
    ngx.header["X-Content-Type-Options"] = "nosniff"
end

return M
