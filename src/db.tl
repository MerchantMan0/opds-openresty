local config = require("lapis.config")
local redis = require("resty.redis")
local type AppConfig = require("lapis.config")
local type Redis = require("resty.redis")
local type Client = Redis.Client

local function release(client: Client, settings: AppConfig.Redis)
   local ok, err = client:set_keepalive(settings.keepalive * 1000, settings.pool_size)
   if not ok then
      error("redis keepalive failed: " .. tostring(err))
   end
end

local function open(): Client, AppConfig.Redis
   local settings = config.get().redis
   local client, new_err = redis:new()
   if not client then
      error("redis failed to connect: " .. tostring(new_err))
   end
   local connected, connect_err = client:connect(settings.host, settings.port, {
      pool = settings.pool_name,
      pool_size = settings.pool_size,
   })
   if not connected then
      error("redis failed to connect: " .. tostring(connect_err))
   end
   local times, times_err = client:get_reused_times()
   if not times then
      error("redis failed to connect: " .. tostring(times_err))
   end
   if times > 0 then
      return client, settings
   end
   if settings.password ~= "" then
      local authed, auth_err = client:auth(settings.password)
      if not authed then
         error("redis auth failed: " .. tostring(auth_err))
      end
   end
   if settings.database ~= 0 then
      local selected, select_err = client:select(settings.database)
      if not selected then
         error("redis select failed: " .. tostring(select_err))
      end
   end
   return client, settings
end

local function send(client: Client, arguments: {string}): any, string
   local method = client[arguments[1]]
   local rest: {string} = {}
   for index = 2, #arguments do
      rest[index - 1] = arguments[index]
   end
   return method(client, unpack(rest))
end

local function failed(value: any, err: string): boolean, string
   if value == nil or value == false then
      return true, err
   end
   if type(value) == "table" then
      local pair = value as {any}
      if pair[1] == false then
         return true, tostring(pair[2])
      end
   end
   return false, ""
end

local function call(arguments: {string}): any
   local client, settings = open()
   local value, err = send(client, arguments)
   local bad, reason = failed(value, err)
   local released, release_err = pcall(function(): string
      release(client, settings)
      return ""
   end)
   if bad then
      error("redis query failed: " .. reason)
   end
   if not released then
      error(release_err as string)
   end
   return value
end

local function pipeline(batches: {{string}}): {any}
   local client, settings = open()
   client:init_pipeline(#batches)
   for _, arguments in ipairs(batches) do
      send(client, arguments)
   end
   local replies, err = client:commit_pipeline()
   local bad = not replies
   local reason = tostring(err)
   if replies then
      for _, reply in ipairs(replies) do
         local reply_bad, reply_reason = failed(reply, "")
         if reply_bad then
            bad = true
            reason = reply_reason
            break
         end
      end
   end
   local released, release_err = pcall(function(): string
      release(client, settings)
      return ""
   end)
   if bad then
      error("redis query failed: " .. reason)
   end
   if not released then
      error(release_err as string)
   end
   return replies as {any}
end

return {
   call = call,
   pipeline = pipeline,
}
