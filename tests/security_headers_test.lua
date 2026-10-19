package.path = "src/?.lua;" .. package.path
local security_headers = require("lua.security_headers")

for _, status in ipairs({200, 204, 301, 401, 403, 404, 429, 500, 502, 504}) do
    for _, upstream in ipairs({false, true}) do
        ngx = {status = status, header = {}}
        if upstream then
            ngx.header["X-Frame-Options"] = {"DENY", "SAMEORIGIN"}
            ngx.header["X-Content-Type-Options"] = {"nosniff", "nosniff"}
        end
        ngx.header["Content-Security-Policy"] = "frame-ancestors 'none'"
        ngx.header["Cache-Control"] = "no-store"
        security_headers.apply()
        security_headers.apply()
        assert(ngx.header["X-Frame-Options"] == "SAMEORIGIN")
        assert(ngx.header["X-Content-Type-Options"] == "nosniff")
        assert(ngx.header["Content-Security-Policy"] == "frame-ancestors 'none'")
        assert(ngx.header["Cache-Control"] == "no-store")
    end
end
print("PASS security headers: duplicates replaced, local/error responses, idempotence, CSP preserved")
