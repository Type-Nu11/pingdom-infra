-- Run from repository root: lua tests/app_entry_test.lua
local cases = {
    {name = "valid app request accepted", ok = true},
    {name = "missing metadata rejected", ok = false, status = 400, message = "missing required header: X-Timestamp"},
    {name = "missing JWT rejected", ok = false, status = 401, message = "missing or invalid authentication token"},
    {name = "invalid JWT rejected", ok = false, status = 401, message = "invalid JWT"},
    {name = "invalid app metadata rejected", ok = false, status = 400, message = "invalid app request headers"}
}

for _, case in ipairs(cases) do
    local calls, status, message = 0, nil, nil
    package.loaded["lua.app_auth"] = {
        validate = function(require_jwt)
            assert(require_jwt == nil, "app routes must require JWT by default")
            calls = calls + 1
            return case.ok, case.status, case.message
        end
    }
    package.loaded["lua.common.response"] = {
        reject = function(code, reason)
            status, message = code, reason
        end
    }
    ngx = {HTTP_BAD_REQUEST = 400, HTTP_UNAUTHORIZED = 401}

    dofile("src/lua/app_entry.lua")

    assert(calls == 1, case.name .. ": auth validation calls")
    assert(status == case.status, case.name .. ": response status")
    assert(message == case.message, case.name .. ": response message")
    print("PASS " .. case.name)
end
