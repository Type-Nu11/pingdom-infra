-- Run from repository root: lua tests/web_entry_test.lua
local cases = {
    {name = "OPTIONS delegates CORS without a token", method = "OPTIONS", requests = 0, jwt = 0},
    {name = "malformed request rejected", bad_request = true, status = 400, jwt = 0},
    {name = "missing JWT rejected", status = 401, jwt = 0},
    {name = "invalid JWT rejected", token = true, invalid_jwt = true, status = 401, jwt = 1},
    {name = "valid request passes JWT and guard", token = true, jwt = 1, guard = 1},
    {name = "blocked request keeps isolation", token = true, blocked = true, jwt = 1, guard = 1, isolated = 1},
}

for _, case in ipairs(cases) do
    local calls = {requests = 0, jwt = 0, guard = 0, isolated = 0}
    local status
    ngx = {HTTP_BAD_REQUEST = 400, HTTP_UNAUTHORIZED = 401,
        req = {get_method = function() return case.method or "GET" end}}
    package.loaded["lua.web_request"] = {build = function()
        calls.requests = calls.requests + 1
        if case.bad_request then return nil, "bad request" end
        return {token = case.token and "test-token" or nil}
    end}
    package.loaded["lua.common.response"] = {reject = function(code) status = code end}
    package.loaded["lua.rust.web_validator"] = {verify = function()
        calls.jwt = calls.jwt + 1
        if case.invalid_jwt then return false, {status = 401, message = "invalid JWT"} end
        return true, {}
    end}
    package.loaded["lua.zig.guard"] = {inspect = function()
        calls.guard = calls.guard + 1
        return not case.blocked, {message = "blocked"}
    end}
    package.loaded["lua.mysterio"] = {isolate = function() calls.isolated = calls.isolated + 1 end}

    dofile("src/lua/web_entry.lua")

    assert(status == case.status, case.name .. ": response status")
    assert(calls.requests == (case.requests or 1), case.name .. ": request parsing")
    assert(calls.jwt == case.jwt, case.name .. ": JWT verification")
    assert(calls.guard == (case.guard or 0), case.name .. ": request guard")
    assert(calls.isolated == (case.isolated or 0), case.name .. ": isolation")
    print("PASS " .. case.name)
end
