local cjson = require("cjson.safe")

local _M = {}

function _M.isolate(req, reason)
    ngx.log(
        ngx.WARN,
        cjson.encode({
            event = "mysterio_isolation",
            request_id = ngx.var.request_id,
            remote_addr = ngx.var.remote_addr,
            method = req.method,
            uri = req.uri,
            user_agent = req.user_agent,
            reason = reason,
            timestamp = ngx.time()
        })
    )

    return ngx.exec("/_mysterio")
end

return _M