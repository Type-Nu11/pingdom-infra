local _M = {}

function _M.isolate(reason)
    ngx.ctx.mysterio_reason = reason
    return ngx.exec("/_mysterio")
end

return _M