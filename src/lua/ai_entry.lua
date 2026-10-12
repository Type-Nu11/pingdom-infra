-- app_entry.lua has already validated the app JWT and metadata in the access phase.
return require("lua.ai_chat").handle()
