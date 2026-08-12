local limit_req = require "resty.limit.req"
local limit_conn = require "resty.limit.conn"

local REQ_DICT = "limit_req_store"
local CONN_DICT = "limit_conn_store"

local function init_limiters()
    local lim_req, err = limit_req.new(REQ_DICT, 10, 80)
    local lim_c, err2 = limit_conn.new(CONN_DICT, 20, 50, 0.5)

    return lim_req, lim_c, (err or err2)
end

local lim_req_default, lim_conn, init_err = init_limiters()

if init_err then
    ngx.log(ngx.ERR, "Limiters Init Error: ", init_err)
end

function _M.limit()
    -- 초기화에 실패한 경우 처리
    if not lim_req_default or not lim_conn then
        return customException.customException(ngx.HTTP_INTERNAL_SERVER_ERROR, "Limiters not ready")
    end

    local ip = ngx.ctx.client_ip or ngx.var.remote_addr

    -- Connection Limit
    local delay, err = lim_conn:incoming(ip, true)
    if not delay then
        if err == "rejected" then
            return nil, err
        end
        return
    end
    ngx.ctx.conn_limited = true

    local is221 = ip:match("^221%.")
    local l_req = is221 and lim_req_221 or lim_req_default

    -- Request Limit
    local delay, err = l_req:incoming(ip, true)
    if not delay then
        if err == "rejected" then
            return nil, err
        end
        return
    end

    if delay > 0 then
        ngx.sleep(delay)
    end
end

function _M.leave()
    -- log_by_lua 단계는 안전이 제일입니다.
    if not lim_conn then return end
    if not ngx.ctx.conn_limited then return end
    
    local ip = ngx.ctx.client_ip or ngx.var.remote_addr
    if not ip then return end

    local latency, err = lim_conn:leaving(ip)
    if not latency then
        -- 여기서도 절대 ngx.say/exit 금지, 오직 로그만!
        ngx.log(ngx.ERR, "Leave error: ", err)
    end
end

return _M