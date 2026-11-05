local config = require("lapis.config")
local List = require("pl.List")
local path = require("pl.path")
local stringx = require("pl.stringx")

local function load_dirs(name: string): {config.FileDir}
   local spec = os.getenv(name)
   if not spec or spec == "" then
      return {}
   end

   local dirs: {config.FileDir} = {}
   local seen = List.new({} as {string})
   for _, raw_entry in ipairs(List.split(spec, ",")) do
      local entry = stringx.strip(raw_entry)
      if entry ~= "" then
         local prefix_raw, _, directory_raw = stringx.partition(entry, "=")
         prefix_raw = stringx.strip(prefix_raw)
         directory_raw = stringx.strip(directory_raw)
         if prefix_raw == "" or directory_raw == "" then
            error(name .. " entry must be prefix=path: " .. entry)
         end

         local directory = path.join(path.abspath(path.normpath(directory_raw), path.currentdir()), "")
         if not path.isdir(directory) then
            error(name .. " path is not a directory: " .. directory)
         end

         local prefix = path.normpath(prefix_raw)
         if not path.isabs(prefix) or prefix == path.sep or prefix == "/static" or prefix == "/favicon.ico" then
            error(name .. " prefix must be a location below / and must not replace /static/ or /favicon.ico: " .. prefix_raw)
         end
         prefix = path.join(prefix, "")
         if prefix:sub(1, #"/static/") == "/static/" then
            error(name .. " prefix must not be under /static/: " .. prefix)
         end
         if seen:contains(prefix) then
            error(name .. " prefix is listed more than once: " .. prefix)
         end
         seen:append(prefix)
         table.insert(dirs, { prefix = prefix, path = directory })
      end
   end

   return dirs
end

local function prefixes_overlap(left: string, right: string): boolean
   if #left < #right then
      return right:sub(1, #left) == left
   end
   return left:sub(1, #right) == right
end

local function reject_prefix_overlap(left_name: string, left_dirs: {config.FileDir}, right_name: string, right_dirs: {config.FileDir})
   for _, right in ipairs(right_dirs) do
      for _, left in ipairs(left_dirs) do
         if prefixes_overlap(right.prefix, left.prefix) then
            error(right_name .. " prefix overlaps " .. left_name .. " prefix " .. left.prefix .. ": " .. right.prefix)
         end
      end
   end
end

local record OpdsDocument
   suffix: string
   type: string
   index: boolean
end

local opds_documents: {OpdsDocument} = {
   { suffix = "nav.xml", type = "application/atom+xml;profile=opds-catalog;kind=navigation", index = true },
   { suffix = "acq.xml", type = "application/atom+xml;profile=opds-catalog;kind=acquisition", index = true },
   { suffix = "entry.xml", type = "application/atom+xml;type=entry;profile=opds-catalog", index = false },
   { suffix = "osd.xml", type = "application/opensearchdescription+xml", index = false },
}

local function pcre_escape(value: string): string
   return (value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?{}|])", "\\%1"))
end

local function load_opds_roots(dirs: {config.FileDir}): {config.OpdsRoot}
   local names: {string} = {}
   for _, document in ipairs(opds_documents) do
      if document.index then
         table.insert(names, "index." .. document.suffix)
      end
   end
   local index = table.concat(names, " ")
   local roots: {config.OpdsRoot} = {}
   for _, dir in ipairs(dirs) do
      local escaped = pcre_escape(dir.prefix)
      local locations: {config.OpdsLocation} = {}
      for _, document in ipairs(opds_documents) do
         table.insert(locations, {
            pattern = "^" .. escaped .. "(.*" .. pcre_escape("." .. document.suffix) .. ")$",
            type = document.type,
         })
      end
      table.insert(roots, {
         prefix = dir.prefix,
         path = dir.path,
         bare = dir.prefix:sub(1, -2),
         deny = "^" .. escaped .. "(.+[^/])$",
         index = index,
         locations = locations,
      })
   end
   return roots
end

local function load_directories(): {config.FileDir}, {config.FileDir}, {config.OpdsRoot}
   local file_dirs = load_dirs("FILE_DIRS")
   local image_dirs = load_dirs("IMAGE_DIRS")
   local opds_dirs = load_dirs("OPDS_DIRS")
   reject_prefix_overlap("FILE_DIRS", file_dirs, "IMAGE_DIRS", image_dirs)
   reject_prefix_overlap("FILE_DIRS", file_dirs, "OPDS_DIRS", opds_dirs)
   reject_prefix_overlap("IMAGE_DIRS", image_dirs, "OPDS_DIRS", opds_dirs)
   return file_dirs, image_dirs, load_opds_roots(opds_dirs)
end

local function positive_integer(name: string, value: string): integer
   local number = tonumber(value)
   if not number or number < 1 or number ~= math.floor(number) then
      error(name .. " must be a positive integer")
   end
   return number as integer
end

local function env_integer(name: string, default: integer): integer
   local value = os.getenv(name)
   if value then
      value = stringx.strip(value)
   end
   if not value or value == "" then
      return default
   end
   return positive_integer(name, value)
end

local function required_env(name: string): string
   local value = os.getenv(name)
   if value then
      value = stringx.strip(value)
   end
   if not value or value == "" then
      error(name .. " is required")
   end
   return value
end

local function nonnegative_integer(name: string, value: string): integer
   local number = tonumber(value)
   if not number or number < 0 or number ~= math.floor(number) then
      error(name .. " must be a non-negative integer")
   end
   return number as integer
end

local function env_nonnegative(name: string, default: integer): integer
   local value = os.getenv(name)
   if value then
      value = stringx.strip(value)
   end
   if not value or value == "" then
      return default
   end
   return nonnegative_integer(name, value)
end

local function optional_env(name: string, default: string): string
   local value = os.getenv(name)
   if value then
      value = stringx.strip(value)
   end
   if not value or value == "" then
      return default
   end
   if value:find("%s") then
      error(name .. " must not contain whitespace")
   end
   return value
end

local function load_redis(): config.Redis
   local host = required_env("REDIS_HOST")
   local port = positive_integer("REDIS_PORT", required_env("REDIS_PORT"))
   local database = env_nonnegative("REDIS_DB", 0)
   local index = optional_env("REDIS_INDEX", "publications")
   local catalog_key = optional_env("REDIS_CATALOG", "catalog")
   return {
      host = host,
      port = port,
      password = os.getenv("REDIS_PASSWORD") or "",
      database = database,
      pool_name = host .. ":" .. tostring(port) .. ":" .. tostring(database) .. ":" .. index,
      pool_size = env_integer("REDIS_POOL_SIZE", 8),
      keepalive = env_integer("REDIS_KEEPALIVE", 60),
      index = index,
      catalog_key = catalog_key,
   }
end

local file_dirs, image_dirs, opds_roots = load_directories()
local redis = load_redis()
local response_ttl = env_integer("RESPONSE_TTL", 300)

config("development", {
   server = "nginx",
   port = 8081,
   num_workers = "1",
   code_cache = "off",
   file_dirs = file_dirs,
   image_dirs = image_dirs,
   opds_roots = opds_roots,
   redis = redis,
   response_ttl = response_ttl,
})

config("production", {
   server = "nginx",
   port = 80,
   num_workers = "4",
   code_cache = "on",
   file_dirs = file_dirs,
   image_dirs = image_dirs,
   opds_roots = opds_roots,
   redis = redis,
   response_ttl = response_ttl,
})
