-- Run from repository root: lua tests/app_entry_test.lua
local original_getenv = os.getenv
local cases = {
    {name = "disabled skips header parsing and HMAC", flag = "false", builds = 0, validations = 0},
    {name = "unset requires headers", builds = 1, validations = 0, build_error = "missing required header: x-timestamp", status = 400},
    {name = "enabled requires headers", flag = "true", builds = 1, validations = 0, build_error = "missing required header: x-timestamp", status = 400},
    {name = "invalid flag keeps enforcement", flag = "FALSE", builds = 1, validations = 0, build_error = "missing required header: x-timestamp", status = 400},
    {name = "invalid signature rejected", flag = "true", builds = 1, validations = 1, validation_error = {status = 401, message = "invalid app request"}, status = 401},
    {name = "missing secret rejected", flag = "true", builds = 1, validations = 1, validation_error = {status = 500, message = "HMAC secret is not configured"}, status = 500},
    {name = "valid HMAC accepted", flag = "true", builds = 1, validations = 1}
}
for _, case in ipairs(cases) do
    local builds, validations, status = 0, 0, nil
    os.getenv = function(key)
        assert(key == "APP_HMAC_ENFORCE")
        return case.flag
    end
    ngx = {HTTP_BAD_REQUEST = 400, HTTP_UNAUTHORIZED = 401}
    package.loaded["lua.app_request"] = {build = function()
        builds = builds + 1
        if case.build_error then return nil, case.build_error end
        return {method = "GET"}
    end}
    package.loaded["lua.rust.app_validator"] = {validate = function(req)
        assert(req.method == "GET")
        validations = validations + 1
        return case.validation_error == nil, case.validation_error
    end}
    package.loaded["lua.common.response"] = {reject = function(code, message)
        assert(type(message) == "string")
        status = code
    end}
    dofile("src/lua/app_entry.lua")
    assert(builds == case.builds, case.name .. ": build calls")
    assert(validations == case.validations, case.name .. ": validator calls")
    assert(status == case.status, case.name .. ": response status")
    print("PASS " .. case.name)
end
os.getenv = original_getenv
