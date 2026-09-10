local ffi = require("ffi")

ffi.cdef[[
int validate_app_request(
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t,
    const uint8_t*, size_t
);

int verify_jwt(
    const uint8_t*, size_t,
    const uint8_t*, size_t
);
]]

local path = os.getenv("RUST_VALIDATOR_LIB")

if not path or path == "" then
    error("APP_VALIDATOR_LIB is not configured")
end

return ffi.load()