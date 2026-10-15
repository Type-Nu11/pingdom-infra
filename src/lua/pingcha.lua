local cjson = require("cjson.safe")
local sha256 = require("resty.sha256")
local random = require("resty.random")
local str = require("resty.string")
local response = require("lua.common.response")
local M = {}
local CHALLENGE_TTL, CLEARANCE_TTL = 120, 900

function M.enabled()
    return os.getenv("PINGCHA_ENABLED") == "true"
end

local function hash(value)
    local digest = assert(sha256:new())
    assert(digest:update(value))
    return str.to_hex(assert(digest:final()))
end

local function secret()
    local bytes = random.bytes(32, true)
    if not bytes then return nil end
    return str.to_hex(bytes)
end

local function agent()
    return hash(ngx.var.http_user_agent or "")
end

local function json(status, value)
    ngx.header["Cache-Control"] = "no-store"
    return response.json(status, value)
end

local function fail(status, code)
    return json(status, {code = code})
end

function M.cleared()
    local token
    -- Cookie names containing '-' are parsed explicitly, avoiding nginx variable normalization.
    local cookies = ngx.var.http_cookie or ""
    for field in cookies:gmatch("[^;]+") do
        local value = field:match("^%s*__Host%-pingcha=([^%s;]+)%s*$")
        if value then
            if token then return false end
            token = value
        end
    end
    if not token or #token ~= 64 or not token:match("^[a-f0-9]+$") then return false end
    return ngx.shared.pingcha_clearances:get(hash(token)) == agent()
end

local function same_origin()
    if ngx.var.http_sec_fetch_site == "cross-site" then return false end
    local origin = ngx.var.http_origin
    if not origin then return true end
    return origin == "https://" .. (ngx.var.http_host or "")
        or (ngx.var.scheme == "http" and origin == "http://" .. (ngx.var.http_host or ""))
end

function M.challenge()
    if ngx.req.get_method() ~= "GET" then return fail(405, "METHOD_NOT_ALLOWED") end
    if not same_origin() then return fail(403, "ORIGIN_REJECTED") end
    if not M.enabled() then return json(200, {enabled = false, verified = false}) end
    if M.cleared() then return json(200, {verified = true, expires_in = CLEARANCE_TTL}) end
    local id, nonce = secret(), secret()
    if not id or not nonce then return fail(503, "PINGCHA_UNAVAILABLE") end
    local stored = ngx.shared.pingcha_challenges:safe_add("challenge:" .. id,
        cjson.encode({nonce = nonce, agent = agent()}), CHALLENGE_TTL)
    if not stored then return fail(503, "PINGCHA_BUSY") end
    return json(200, {id = id, nonce = nonce, difficulty = 10, expires_in = CHALLENGE_TTL})
end

function M.status()
    if ngx.req.get_method() ~= "GET" then return fail(405, "METHOD_NOT_ALLOWED") end
    if not same_origin() then return fail(403, "ORIGIN_REJECTED") end
    local enabled = M.enabled()
    return json(200, {enabled = enabled, verified = enabled and M.cleared() or false})
end

function M.verify()
    if ngx.req.get_method() ~= "POST" then return fail(405, "METHOD_NOT_ALLOWED") end
    if not same_origin() then return fail(403, "ORIGIN_REJECTED") end
    if not M.enabled() then return json(200, {enabled = false, verified = false}) end
    if not (ngx.var.content_type or ""):match("^application/json") then
        return fail(415, "JSON_REQUIRED")
    end
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body or #body > 1024 then return fail(400, "INVALID_PROOF") end
    local proof = cjson.decode(body)
    if type(proof) ~= "table" or type(proof.id) ~= "string" or #proof.id ~= 64
        or not proof.id:match("^[a-f0-9]+$") or type(proof.counter) ~= "number"
        or proof.counter ~= math.floor(proof.counter) or proof.counter < 0 or proof.counter >= 16384 then
        return fail(400, "INVALID_PROOF")
    end
    local dict = ngx.shared.pingcha_challenges
    local challenge = cjson.decode(dict:get("challenge:" .. proof.id) or "")
    if not challenge then return fail(403, "CHALLENGE_EXPIRED") end
    if challenge.agent ~= agent() then return fail(403, "CHALLENGE_MISMATCH") end
    local digest = hash(challenge.nonce .. ":" .. string.format("%.0f", proof.counter))
    -- Ten leading zero bits, fixed by the server, never supplied by the client.
    if digest:sub(1, 2) ~= "00" or tonumber(digest:sub(3, 3), 16) >= 4 then
        return fail(403, "INVALID_PROOF")
    end
    local token = secret()
    if not token then return fail(503, "PINGCHA_UNAVAILABLE") end
    -- Atomic claim prevents two workers from accepting the same proof concurrently.
    if not dict:safe_add("used:" .. proof.id, true, CHALLENGE_TTL) then
        return fail(403, "CHALLENGE_ALREADY_USED")
    end
    dict:delete("challenge:" .. proof.id)
    if not ngx.shared.pingcha_clearances:safe_add(hash(token), agent(), CLEARANCE_TTL) then
        return fail(503, "PINGCHA_BUSY")
    end
    ngx.header["Set-Cookie"] = "__Host-pingcha=" .. token
        .. "; Path=/; Max-Age=" .. CLEARANCE_TTL .. "; Secure; HttpOnly; SameSite=Lax"
    return json(200, {verified = true, expires_in = CLEARANCE_TTL})
end

function M.modal_page(uri)
    if not (uri:match("^/console/") or uri == "/login" or uri == "/signup") then return false end
    local extension = uri:match("%.([%w]+)$")
    local static = {js = true, css = true, mjs = true, png = true, jpg = true, jpeg = true,
        svg = true, gif = true, ico = true, webp = true, woff = true, woff2 = true, map = true}
    return not (extension and static[extension:lower()])
end

function M.protected(uri, method, accept)
    if method == "OPTIONS" then return false end
    local path = uri:gsub("^/api/", "/")
    -- Refresh/logout and OAuth callbacks retain their backend token/state validation.
    if path == "/auth/refresh" or path == "/auth/logout"
        or path:match("^/auth/.*/callback$") or path:match("^/auth/callback") then return false end
    if path:match("^/auth/") then return true end
    if path:match("^/v3/api%-docs/") then return true end
    if uri:match("^/swagger%-ui") and (uri:match("%.html$") or uri:sub(-1) == "/") then return true end
    return method == "GET" and (accept or ""):find("text/html", 1, true) ~= nil
        and M.modal_page(uri)
end

function M.enforce()
    if not M.enabled() then return end
    -- Let console HTML render; the response filter mounts PingCha on top of it.
    -- Credential/API requests still require a server-validated clearance below.
    if ngx.req.get_method() == "GET" and M.modal_page(ngx.var.uri) then return end
    if not M.protected(ngx.var.uri, ngx.req.get_method(), ngx.var.http_accept) or M.cleared() then return end
    ngx.header["Cache-Control"] = "no-store"
    local url = "/_pingdom/captcha/?return_to=" .. ngx.escape_uri(ngx.var.request_uri)
    if ngx.req.get_method() == "GET" and (ngx.var.http_accept or ""):find("text/html", 1, true) then
        return ngx.redirect(url, 302)
    end
    return json(403, {code = "PINGCHA_REQUIRED", challenge_url = url})
end

return M
