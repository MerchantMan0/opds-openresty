local record stringx
   partition: function(string, string): string, string, string
   replace: function(string, string, string, ?number): string
   split: function(string, ?string): {string}
   strip: function(string, ?string): string
end

return stringx
