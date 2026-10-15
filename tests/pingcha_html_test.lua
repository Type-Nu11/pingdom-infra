package.loaded["resty.random"] = {bytes = function() return "random" end}
package.loaded["resty.string"] = {to_hex = function() return "test-nonce" end}
package.loaded["lua.pingcha"] = {enabled = function() return true end,
    modal_page = function(uri) return uri == "/console/login" end}
local html = dofile("src/lua/pingcha_html.lua")

local function setup(content_type, policy)
    ngx = {
        req = {get_method = function() return "GET" end}, status = 200,
        var = {uri = "/console/login"}, ctx = {},
        header = {content_type = content_type or "text/html", content_length = 100,
            ["Content-Security-Policy"] = policy, ETag = "old"},
        log = function() end,
    }
end

setup("text/html", "default-src 'self'; script-src 'none'; object-src 'none'; frame-src 'none'")
html.header()
assert(not ngx.header.content_length and not ngx.header.ETag)
assert(ngx.header["Content-Security-Policy"]:find("script%-src%s+'nonce%-test%-nonce'"))
assert(ngx.header["Content-Security-Policy"]:find("object%-src 'none'"))
local pieces = {}
local chunks = {"<html><body>" .. string.rep("x", 1000), "hello</bo", "dy></html>"}
for i, chunk in ipairs(chunks) do
    ngx.arg = {chunk, i == #chunks}
    html.body()
    pieces[#pieces + 1] = ngx.arg[1]
end
local result = table.concat(pieces)
assert(result:find('hello<script defer nonce="test%-nonce" src="/_pingdom/captcha/modal.js"></script></body>'))
assert(select(2, result:gsub("modal.js", "")) == 1)
assert(#result == #table.concat(chunks) + #ngx.ctx.pingcha_html.script)

setup("text/html", "object-src 'none'")
html.header()
assert(ngx.header["Content-Security-Policy"] == "object-src 'none'", "Do not restrict formerly unrestricted script/style directives")
setup("application/json")
html.header()
assert(not ngx.ctx.pingcha_html, "Do not rewrite APIs")
setup()
ngx.header["Content-Encoding"] = "gzip"
html.header()
assert(not ngx.ctx.pingcha_html, "Never corrupt a compressed response")
setup()
html.header()
ngx.arg = {"<html>fragment", true}
html.body()
assert(ngx.arg[1]:find("modal.js", 1, true), "HTML fragments still receive a loader")
print("PASS PingCha HTML: chunk boundaries, CSP preservation, JSON/encoding exclusions")
setup()
package.loaded["lua.pingcha"].enabled = function() return false end
html.header()
assert(not ngx.ctx.pingcha_html and ngx.header.content_length == 100 and ngx.header.ETag == "old")
print("PASS PingCha disabled: HTML/headers remain untouched")
