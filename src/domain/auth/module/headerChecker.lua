local bit = require("bit")
local sha256 = require("resty.sha256")

local _M = {}
local TIMESTAMP_TTL = 60
local UUID_PATTERN = "^[0-9a-fA-F]{8}%-[0-9a-fA-F]{4}%-[0-9a-fA-F]{4}%-[0-9a-fA-F]{4}%-[0-9a-fA-F]{12}$"
local SEMVER_PATTERN = "^%d+%.%d+%.%d+$"

local function load_dotenv()
    local ok, dotenv = pcall(require, "luadotenv")
    if not ok or not dotenv then
        ngx.log(ngx.WARN, "luadotenv module not available; .env not loaded")
        return
    end

    local env_path = ".env"
    if not io.open(env_path, "r") then
        local prefix = ngx.config.prefix() or ""
        local alt_path = prefix .. ".env"
        if io.open(alt_path, "r") then
            env_path = alt_path
        end
    end

    local ok2, err = pcall(dotenv.config, { path = env_path })
    if not ok2 then
        ngx.log(ngx.ERR, "Failed to load .env via luadotenv: ", err)
    end
end

load_dotenv()

local function reject(reason)
    ngx.log(ngx.ERR, "Header validation failed: ", reason)
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.say("Forbidden: ", reason)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

local function trim(value)
    if not value then
        return nil
    end
    return value:gsub("^%s*(.-)%s*$", "%1")
end

local function is_valid_timestamp(value)
    local timestamp = tonumber(trim(value))
    if not timestamp or timestamp <= 0 then
        return false
    end

    return math.abs(ngx.time() - timestamp) <= TIMESTAMP_TTL
end

local function is_valid_semver(value)
    return value and value:match(SEMVER_PATTERN)
end

local function is_valid_uuid(value)
    return value and value:match(UUID_PATTERN)
end

local function get_request_body()
    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if body then
        return body
    end

    local body_file = ngx.req.get_body_file()
    if body_file then
        local f, err = io.open(body_file, "rb")
        if not f then
            ngx.log(ngx.ERR, "Failed to read request body file: ", err)
            return ""
        end
        body = f:read("*a")
        f:close()
        return body or ""
    end

    return ""
end

local function hmac_sha256(key, message)
    local block_size = 64

    if #key > block_size then
        local khash = sha256:new()
        khash:update(key)
        key = khash:final()
    end

    if #key < block_size then
        key = key .. string.rep("\0", block_size - #key)
    end

    local i_key_pad = key:gsub(".", function(c)
        return string.char(bit.bxor(string.byte(c), 0x36))
    end)
    local o_key_pad = key:gsub(".", function(c)
        return string.char(bit.bxor(string.byte(c), 0x5c))
    end)

    local inner = sha256:new()
    inner:update(i_key_pad)
    inner:update(message)
    local inner_hash = inner:final()

    local outer = sha256:new()
    outer:update(o_key_pad)
    outer:update(inner_hash)
    return outer:final()
end

local function build_signature_payload(method, request_uri, timestamp, app_version, device_id, body)
    return table.concat({
        method,
        request_uri or "",
        timestamp,
        app_version,
        device_id,
        body
    }, "|")
end

function _M.check()
    local headers = ngx.req.get_headers()
    local timestamp = trim(headers["x-timestamp"])
    local app_version = trim(headers["x-app-version"])
    local device_id = trim(headers["x-device-id"])
    local signature = trim(headers["x-signaturebase64"])
    local secret = os.getenv("HMAC_SECRET_KEY")

    if not timestamp then
        return reject("Missing X-Timestamp")
    end
    if not is_valid_timestamp(timestamp) then
        return reject("Invalid X-Timestamp")
    end

    if not app_version then
        return reject("Missing X-App-Version")
    end
    if not is_valid_semver(app_version) then
        return reject("Invalid X-App-Version")
    end

    if not device_id then
        return reject("Missing X-Device-Id")
    end
    if not is_valid_uuid(device_id) then
        return reject("Invalid X-Device-Id")
    end

    if not signature then
        return reject("Missing X-SignatureBase64")
    end

    if not secret or secret == "" then
        secret = os.getenv("SECRET_KEY")
    end

    if not secret or secret == "" then
        ngx.log(ngx.ERR, "HMAC secret key is not configured")
        return reject("Server misconfiguration")
    end

    local body = get_request_body()
    local payload = build_signature_payload(
        ngx.req.get_method(),
        ngx.var.request_uri,
        timestamp,
        app_version,
        device_id,
        body
    )
    local expected = ngx.encode_base64(hmac_sha256(secret, payload))

    if signature ~= expected then
        return reject("Invalid X-SignatureBase64")
    end
end

return _M

