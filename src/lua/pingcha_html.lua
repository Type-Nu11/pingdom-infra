local random = require("resty.random")
local str = require("resty.string")
local pingcha = require("lua.pingcha")
local M = {}

-- Preserve upstream policies and authorize only our nonce-bearing loader/style.
local function policy_with_nonce(policy, nonce)
    local directives, order = {}, {}
    for part in policy:gmatch("[^;]+") do
        local name, value = part:match("^%s*([%w%-]+)%s*(.-)%s*$")
        if name and not directives[name:lower()] then
            name = name:lower()
            directives[name] = value
            order[#order + 1] = name
        end
    end
    local function add(name, source, fallback)
        local value = directives[name]
        if value == nil then
            value = (fallback and directives[fallback]) or directives["default-src"]
            -- An absent directive/default is unrestricted; do not restrict the host app.
            if value == nil then return end
            order[#order + 1] = name
        end
        value = value:gsub("'none'", "")
        directives[name] = value .. " " .. source
    end
    local source = "'nonce-" .. nonce .. "'"
    add("script-src", source)
    if directives["script-src-elem"] then add("script-src-elem", source) end
    add("style-src", source)
    if directives["style-src-elem"] then add("style-src-elem", source) end
    add("frame-src", "'self'", "child-src")
    add("connect-src", "'self'")
    local result = {}
    for _, name in ipairs(order) do result[#result + 1] = name .. " " .. directives[name] end
    return table.concat(result, "; ")
end

function M.header()
    if not pingcha.enabled() then return end
    if ngx.req.get_method() ~= "GET" or ngx.status ~= 200 or not pingcha.modal_page(ngx.var.uri) then return end
    if not (ngx.header.content_type or ""):lower():find("text/html", 1, true) then return end
    local encoding = ngx.header["Content-Encoding"]
    if encoding and encoding ~= "identity" then
        ngx.log(ngx.WARN, "PingCha: HTML injection skipped for encoded upstream response")
        return
    end
    local bytes = random.bytes(16, true)
    if not bytes then
        ngx.log(ngx.ERR, "PingCha: failed to create HTML nonce")
        return
    end
    local nonce = str.to_hex(bytes)
    ngx.ctx.pingcha_html = {tail = "", script = '<script defer nonce="' .. nonce
        .. '" src="/_pingdom/captcha/modal.js"></script>'}
    ngx.header.content_length = nil
    ngx.header["ETag"] = nil
    ngx.header["Last-Modified"] = nil
    ngx.header["Content-MD5"] = nil
    ngx.header["Content-Digest"] = nil
    ngx.header["Cache-Control"] = "no-store"
    for _, name in ipairs({"Content-Security-Policy", "Content-Security-Policy-Report-Only"}) do
        local policy = ngx.header[name]
        if type(policy) == "table" then
            for i, value in ipairs(policy) do policy[i] = policy_with_nonce(value, nonce) end
            ngx.header[name] = policy
        elseif policy then
            ngx.header[name] = policy_with_nonce(policy, nonce)
        end
    end
end

function M.body()
    local state = ngx.ctx.pingcha_html
    if not state or state.injected then return end
    local buffer = state.tail .. (ngx.arg[1] or "")
    if ngx.arg[2] then
        -- Search only the final tail, avoiding body-like strings inside large app scripts.
        local start, position = nil, 1
        while true do
            local first, last = buffer:find("</[bB][oO][dD][yY]%s*>", position)
            if not first then break end
            start, position = first, last + 1
        end
        ngx.arg[1] = start and (buffer:sub(1, start - 1) .. state.script .. buffer:sub(start))
            or (buffer .. state.script)
        state.tail, state.injected = "", true
    else
        -- Bounded tail handles a closing body tag split across upstream chunks.
        local cut = math.max(0, #buffer - 256)
        ngx.arg[1], state.tail = buffer:sub(1, cut), buffer:sub(cut + 1)
    end
end

return M
