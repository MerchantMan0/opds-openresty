local record application
   match: function(self: application, path: string, handler: function(any): any, string)
end

local record lapis
   Application: function(): application
   serve: function(name: string)
end

return lapis
