local record lapis_config
   record FileDir
      prefix: string
      path: string
   end

   record OpdsLocation
      pattern: string
      type: string
   end

   record OpdsRoot
      prefix: string
      path: string
      bare: string
      deny: string
      index: string
      locations: {OpdsLocation}
   end

   record Redis
      host: string
      port: integer
      password: string
      database: integer
      pool_name: string
      pool_size: integer
      keepalive: integer
      index: string
      catalog_key: string
   end

   record ConfigValues
      server: string
      port: integer
      num_workers: string
      code_cache: string
      file_dirs: {FileDir}
      image_dirs: {FileDir}
      opds_roots: {OpdsRoot}
      redis: Redis
      response_ttl: integer
      _name: string | nil
   end

   metamethod __call: function(self: lapis_config, environment: string, values: ConfigValues)
   get: function(name?: string): ConfigValues
end

return lapis_config
