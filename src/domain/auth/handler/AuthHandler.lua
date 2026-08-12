local headerChecker = require("headerChecker")
local firewall = require("Firewall")

headerChecker.check()
firewall.new():run()

