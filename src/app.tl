local config = require("lapis.config")
local lapis = require("lapis")
local feed = require("opds.feed")

local app = lapis.Application()

for _, root in ipairs(config.get().opds_roots) do
   local prefix = root.prefix
   app:match(prefix .. "search", function(request: any): {string: any}, string
      return feed.render(request, prefix, "Search")
   end)
   app:match(prefix .. "browse", function(request: any): {string: any}, string
      return feed.render(request, prefix, "Browse")
   end)
end

return app
