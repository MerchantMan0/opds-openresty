global record ngx
   record SharedDict
      get: function(self: SharedDict, key: string): any
      set: function(self: SharedDict, key: string, value: string, exptime: number): boolean, string
      flush_expired: function(self: SharedDict): number
   end

   escape_uri: function(string): string
   encode_args: function({string: string}): string
   log: function(number, ...: any)
   md5: function(string): string
   var: {string: string}
   shared: {string: SharedDict}
   ERR: number
end

global unpack: function<A>({A}): A...
