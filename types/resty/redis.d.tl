local record resty_redis
   record ConnectOptions
      pool: string
      pool_size: integer
   end

   record Client
      connect: function(self: Client, host: string, port: integer, options: ConnectOptions): boolean, string
      get_reused_times: function(self: Client): integer, string
      auth: function(self: Client, password: string): boolean, string
      select: function(self: Client, database: integer): boolean, string
      set_keepalive: function(self: Client, timeout: integer, size: integer): boolean, string
      init_pipeline: function(self: Client, count: integer)
      commit_pipeline: function(self: Client): {any}, string
      metamethod __index: function(self: Client, command: string): function(self: Client, ...: string): any, string
   end

   new: function(self: resty_redis): Client, string
end

return resty_redis
