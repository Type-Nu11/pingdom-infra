local json = require("cjson.safe").new()
local response = require("lua.common.response")
local _M = {}

-- Preserve [] versus {} in schemas, arguments and empty tool-call responses.
json.decode_array_with_array_mt(true)
json.decode_invalid_numbers(false)
json.encode_invalid_numbers(false)
json.decode_max_depth(64)

local function array(value)
    return type(value) == "table" and getmetatable(value) == json.array_mt
end

local function object(value)
    return type(value) == "table" and not array(value)
end

local function text(value, limit)
    return type(value) == "string" and value:find("%S") ~= nil and #value <= limit
end

local function tool_call(call, names, from_provider)
    if not object(call) or not text(call.id, 256) or call.type ~= "function"
        or not object(call["function"]) then
        return nil
    end
    local func = call["function"]
    if type(func.name) ~= "string" or not names[func.name] then return nil end
    local arguments = func.arguments
    if from_provider then
        if type(arguments) ~= "string" then return nil end
        arguments = json.decode(arguments)
    end
    if not object(arguments) then return nil end
    if not from_provider then
        arguments = json.encode(arguments)
        if not arguments then return nil end
    end
    return {id = call.id, type = "function", ["function"] = {
        name = func.name, arguments = arguments
    }}
end

local function request_payload(input, model)
    if not object(input) or not array(input.messages) or #input.messages == 0
        or #input.messages > 50 then return nil end
    local tools = input.tools
    if tools == nil or tools == json.null then tools = json.empty_array end
    local names, output_tools = {}, setmetatable({}, json.array_mt)
    if tools ~= json.empty_array then
        if not array(tools) or #tools > 20 then return nil end
        for _, tool in ipairs(tools) do
            if not object(tool) or tool.type ~= "function" or not object(tool["function"]) then
                return nil
            end
            local func = tool["function"]
            if not text(func.name, 64) or not func.name:match("^[A-Za-z_][A-Za-z0-9_-]*$")
                or names[func.name] or not text(func.description, 2000)
                or not object(func.parameters) or func.parameters.type ~= "object"
                or not object(func.parameters.properties) then return nil end
            if func.parameters.required ~= nil and not array(func.parameters.required) then return nil end
            names[func.name] = true
            output_tools[#output_tools + 1] = {type = "function", ["function"] = {
                name = func.name, description = func.description, parameters = func.parameters
            }}
        end
    end
    local messages, pending, seen = setmetatable({}, json.array_mt), {}, {}
    for _, message in ipairs(input.messages) do
        if not object(message) then return nil end
        local calls = message.tool_calls
        if calls == nil or calls == json.null then calls = json.empty_array end
        if calls ~= json.empty_array and (not array(calls) or #calls > 20) then return nil end
        local has_calls = calls ~= json.empty_array and #calls > 0
        local output = {role = message.role}
        if message.role == "user" then
            if not text(message.content, 32000) or has_calls
                or (message.tool_call_id ~= nil and message.tool_call_id ~= json.null) then return nil end
            output.content = message.content
        elseif message.role == "assistant" then
            if message.content ~= nil and message.content ~= json.null
                and not text(message.content, 32000) then return nil end
            if not text(message.content, 32000) and not has_calls then return nil end
            output.content = message.content or json.null
            if has_calls then
                output.tool_calls = setmetatable({}, json.array_mt)
                for _, call in ipairs(calls) do
                    local converted = tool_call(call, names, false)
                    if not converted or seen[converted.id] then return nil end
                    seen[converted.id], pending[converted.id] = true, true
                    output.tool_calls[#output.tool_calls + 1] = converted
                end
            end
        elseif message.role == "tool" then
            if not text(message.tool_call_id, 256) or not pending[message.tool_call_id]
                or message.content == nil or message.content == json.null or has_calls then return nil end
            pending[message.tool_call_id] = nil
            output.tool_call_id = message.tool_call_id
            -- App tool results may be JSON objects; Groq requires string content.
            output.content = type(message.content) == "string" and message.content or json.encode(message.content)
            if not output.content then return nil end
        else
            return nil
        end
        messages[#messages + 1] = output
    end
    local last = messages[#messages].role
    if (last ~= "user" and last ~= "tool") or next(pending) then return nil end
    -- Provider options are server-owned, even if an app supplies extra fields.
    local payload = {model = model, messages = messages, stream = false}
    if #output_tools > 0 then payload.tools = output_tools end
    return json.encode(payload), names
end

local function public_response(body, names)
    local input = json.decode(body)
    if not object(input) or not array(input.choices) or #input.choices ~= 1
        or not object(input.choices[1]) or not object(input.choices[1].message) then return nil end
    local choice, calls = input.choices[1], setmetatable({}, json.array_mt)
    local message = choice.message
    -- Never pass truncated tool arguments or incomplete choices to the app.
    if choice.finish_reason ~= "stop" and choice.finish_reason ~= "tool_calls" then return nil end
    if message.role ~= "assistant" then return nil end
    if message.tool_calls ~= nil and message.tool_calls ~= json.null then
        if not array(message.tool_calls) or #message.tool_calls > 20 then return nil end
        local ids = {}
        for _, call in ipairs(message.tool_calls) do
            local converted = tool_call(call, names, true)
            if not converted or ids[converted.id] then return nil end
            ids[converted.id] = true
            calls[#calls + 1] = converted
        end
    end
    if message.content ~= nil and message.content ~= json.null
        and type(message.content) ~= "string" then return nil end
    if not text(message.content, 2 * 1024 * 1024) and #calls == 0 then return nil end
    local output = {tool_calls = calls}
    if message.content ~= nil and message.content ~= json.null then output.content = message.content end
    -- Encode with this instance so an empty list remains [] (not {}).
    return json.encode(output)
end

local function read_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if body then return body end
    local path = ngx.req.get_body_file()
    if not path then return nil end
    local file = io.open(path, "rb")
    if not file then return nil end
    body = file:read(1024 * 1024 + 1)
    file:close()
    return body
end

function _M.handle()
    local headers = ngx.req.get_headers()
    local request_id = headers["x-request-id"]
    if type(request_id) ~= "string" or #request_id > 128
        or not request_id:match("^[A-Za-z0-9_-]+$") then request_id = ngx.var.request_id end
    ngx.var.ai_request_id = request_id
    ngx.header["X-Request-Id"] = request_id
    local model = os.getenv("AI_MODEL")
    if not model or model == "" then model = "openai/gpt-oss-20b" end

    local function reject(status, code, outcome)
        ngx.log(ngx.WARN, "ai_chat request_id=", request_id, " provider=groq status=", status,
            " outcome=", outcome)
        return response.reject(status, code)
    end

    if ngx.req.get_method() ~= "POST" then
        ngx.header.Allow = "POST"
        return reject(405, "CHAT_METHOD_NOT_ALLOWED", "method_invalid")
    end
    local content_type = headers["content-type"]
    local media_type = type(content_type) == "string" and content_type:lower():match("^%s*([^;]+)")
    if not media_type or media_type:gsub("%s+$", "") ~= "application/json" then
        return reject(415, "CHAT_CONTENT_TYPE_INVALID", "content_type_invalid")
    end
    local body = read_body()
    if not body or #body > 1024 * 1024 then return reject(400, "CHAT_REQUEST_INVALID", "body_invalid") end
    local payload, names = request_payload(json.decode(body), model)
    if not payload then return reject(400, "CHAT_REQUEST_INVALID", "request_invalid") end
    local key = os.getenv("AI_API_KEY")
    if not key or key == "" or not model:match("^[A-Za-z0-9_./-]+$") or #model > 128 then
        return reject(503, "PROVIDER_UNAVAILABLE", "configuration_missing")
    end
    local ok, result = pcall(ngx.location.capture, "/_internal/ai/groq-chat", {
        method = ngx.HTTP_POST, body = payload,
        vars = {groq_authorization = "Bearer " .. key, ai_request_id = request_id}
    })
    if not ok or not result then return reject(502, "PROVIDER_UNAVAILABLE", "transport_failed") end
    if result.status == 429 then
        return reject(429, "PROVIDER_RATE_LIMITED", "provider_rate_limited")
    end
    if result.status < 200 or result.status >= 300 then
        -- Provider bodies may contain user input and account details; do not expose them.
        return reject(502, "PROVIDER_UNAVAILABLE", "provider_failed")
    end
    if result.truncated or not result.body or #result.body > 2 * 1024 * 1024 then
        return reject(502, "PROVIDER_RESPONSE_INVALID", "response_incomplete")
    end
    local output = public_response(result.body, names)
    if not output then return reject(502, "PROVIDER_RESPONSE_INVALID", "response_invalid") end
    ngx.log(ngx.INFO, "ai_chat request_id=", request_id, " provider=groq model=", model,
        " status=200 outcome=success")
    ngx.status = ngx.HTTP_OK
    ngx.header.content_type = "application/json"
    ngx.print(output)
end

return _M
