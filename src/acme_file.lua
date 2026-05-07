local autossl = require("resty.acme.autossl")

local _M = {}

function _M.init()
    autossl.init({
        tos_accepted = true,
        account_email = "cruisesa542@email.com",

        api_endpoint = "https://acme.zerossl.com/v2/DV90",

        eab_kid = os.getenv("EAB_KID"),
        eab_hmac_key = os.getenv("EAB_HMAC_KEY"),

        storage_adapter = "file",
        storage_config = { dir = "/etc/acme" },

        domain_whitelist = { "api.clash.kr" },

        allow_any_domain = false,
    })
end

return _M