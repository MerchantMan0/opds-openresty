local cjson = require("cjson")
local config = require("lapis.config")
local database = require("db")
local search = require("opds.search")

local ACQUISITION_TYPE = "application/atom+xml;profile=opds-catalog;kind=acquisition"
local ATOM = "http://www.w3.org/2005/Atom"
local DC = "http://purl.org/dc/terms"
local OPDS = "http://opds-spec.org/2010/catalog"
local OPENSEARCH = "http://a9.com/-/spec/opensearch/1.1/"

local acquisition_rel: {string: string} = {
   acquisition = "http://opds-spec.org/acquisition",
   ["open-access"] = "http://opds-spec.org/acquisition/open-access",
   borrow = "http://opds-spec.org/acquisition/borrow",
   buy = "http://opds-spec.org/acquisition/buy",
   sample = "http://opds-spec.org/acquisition/sample",
   subscribe = "http://opds-spec.org/acquisition/subscribe",
   preview = "preview",
}

local image_rel: {string: string} = {
   image = "http://opds-spec.org/image",
   thumbnail = "http://opds-spec.org/image/thumbnail",
}

local function escape(value: string): string
   return (value:gsub("[&<>\"]", function(char: string): string
      if char == "&" then
         return "&amp;"
      elseif char == "<" then
         return "&lt;"
      elseif char == ">" then
         return "&gt;"
      end
      return "&quot;"
   end))
end

local function text(value: any): string
   if type(value) == "string" then
      return value as string
   end
   if type(value) == "number" then
      return tostring(value)
   end
   return ""
end

local function list(value: any): {any}
   if type(value) ~= "table" then
      local empty: {any} = {}
      return empty
   end
   return value as {any}
end

local function object(value: any): {string: any}
   if type(value) ~= "table" then
      local empty: {string: any} = {}
      return empty
   end
   return value as {string: any}
end

local function add(parts: {string}, value: string)
   table.insert(parts, value)
end

local function element(parts: {string}, name: string, value: string)
   if value == "" then
      return
   end
   add(parts, "<")
   add(parts, name)
   add(parts, ">")
   add(parts, escape(value))
   add(parts, "</")
   add(parts, name)
   add(parts, ">")
end

local function quote_name(name: string): string
   local parts: {string} = {}
   for part in name:gmatch("[^/]+") do
      if part == ".." then
         error("invalid file name: " .. name)
      end
      if part ~= "." then
         table.insert(parts, ngx.escape_uri(part))
      end
   end
   if #parts == 0 then
      error("invalid file name: " .. name)
   end
   return table.concat(parts, "/")
end

local function directory_map(dirs: {config.FileDir}): {string: string}
   local found: {string: string} = {}
   for _, dir in ipairs(dirs) do
      found[dir.path] = dir.prefix
   end
   return found
end

local function located(base: string, directory: string, name: string, directories: {string: string}): string
   local prefix = directories[directory]
   if not prefix then
      error("directory is not served: " .. directory)
   end
   local path = prefix .. quote_name(name)
   if base == "" then
      return path
   end
   return base .. path
end

local record Incoming
   headers: {string: any}
end

local record Request
   req: Incoming
   GET: {string: any}
end

local function origin(request: Request): string
   local incoming = request.req
   if not incoming or not incoming.headers then
      return ""
   end
   local host = incoming.headers["host"] or incoming.headers["Host"]
   if type(host) ~= "string" or host == "" then
      return ""
   end
   return ngx.var.scheme .. "://" .. (host as string)
end

local function person(parts: {string}, tag: string, value: any)
   local row = object(value)
   local name = text(row.name)
   if name == "" then
      return
   end
   add(parts, "<")
   add(parts, tag)
   add(parts, ">")
   element(parts, "name", name)
   element(parts, "uri", text(row.uri))
   element(parts, "email", text(row.email))
   add(parts, "</")
   add(parts, tag)
   add(parts, ">")
end

local function indirect(parts: {string}, value: any)
   for _, item in ipairs(list(value)) do
      local row = object(item)
      add(parts, '<indirectAcquisition xmlns="' .. OPDS .. '" type="' .. escape(text(row.media_type)) .. '">')
      indirect(parts, row.children)
      add(parts, "</indirectAcquisition>")
   end
end

local function entry(parts: {string}, document: any, base: string, files: {string: string}, images: {string: string})
   local row = object(document)
   add(parts, "<entry>")
   element(parts, "id", text(row.entry_key))
   element(parts, "title", text(row.title))
   element(parts, "updated", text(row.updated))
   element(parts, "published", text(row.published))
   for _, author in ipairs(list(row.authors)) do
      person(parts, "author", author)
   end
   for _, contributor in ipairs(list(row.contributors)) do
      person(parts, "contributor", contributor)
   end
   for _, category in ipairs(list(row.categories)) do
      local item = object(category)
      local term = text(item.term)
      if term ~= "" then
         add(parts, '<category term="' .. escape(term) .. '"')
         local scheme = text(item.scheme)
         local label = text(item.label)
         if scheme ~= "" then
            add(parts, ' scheme="' .. escape(scheme) .. '"')
         end
         if label ~= "" then
            add(parts, ' label="' .. escape(label) .. '"')
         end
         add(parts, "/>")
      end
   end
   element(parts, "rights", text(row.rights))
   local summary = text(row.summary)
   if summary ~= "" then
      add(parts, '<summary type="' .. escape(text(row.summary_type)) .. '">')
      add(parts, escape(summary))
      add(parts, "</summary>")
   end
   for _, identifier in ipairs(list(row.identifiers)) do
      element(parts, "dc:identifier", text(identifier))
   end
   element(parts, "dc:issued", text(row.issued))
   element(parts, "dc:language", text(row.language))
   element(parts, "dc:publisher", text(row.publisher))
   for _, acquisition in ipairs(list(row.acquisitions)) do
      local item = object(acquisition)
      local directory = text(item.directory)
      local href = ""
      if directory ~= "" then
         href = located(base, directory, text(item.name), files)
      else
         href = text(item.href)
      end
      local relation = text(item.relation)
      add(parts, '<link rel="' .. escape(acquisition_rel[relation] or relation) .. '" href="' .. escape(href) .. '"')
      local media_type = text(item.media_type)
      local language = text(item.language)
      local link_title = text(item.title)
      local length = text(item.length)
      if media_type ~= "" then
         add(parts, ' type="' .. escape(media_type) .. '"')
      end
      if language ~= "" then
         add(parts, ' hreflang="' .. escape(language) .. '"')
      end
      if link_title ~= "" then
         add(parts, ' title="' .. escape(link_title) .. '"')
      end
      if length ~= "" then
         add(parts, ' length="' .. escape(length) .. '"')
      end
      add(parts, ">")
      indirect(parts, item.indirect)
      for _, price in ipairs(list(item.prices)) do
         local amount = object(price)
         add(parts, '<price xmlns="' .. OPDS .. '" currencycode="' .. escape(text(amount.currency_code)) .. '">')
         add(parts, escape(text(amount.amount)))
         add(parts, "</price>")
      end
      add(parts, "</link>")
   end
   for _, image in ipairs(list(row.images)) do
      local item = object(image)
      local kind = text(item.kind)
      local href = located(base, text(item.directory), text(item.name), images)
      add(parts, '<link rel="' .. escape(image_rel[kind] or kind) .. '" href="' .. escape(href) .. '"')
      local media_type = text(item.media_type)
      if media_type ~= "" then
         add(parts, ' type="' .. escape(media_type) .. '"')
      end
      add(parts, "/>")
   end
   add(parts, "</entry>")
end

local function catalog_of(reply: any): {string: any}
   if type(reply) ~= "string" or reply == "" then
      local empty: {string: any} = {}
      return empty
   end
   local ok, decoded = pcall(cjson.decode, reply as string)
   if not ok or type(decoded) ~= "table" then
      local empty: {string: any} = {}
      return empty
   end
   return decoded as {string: any}
end

local function render(request: any, prefix: string, title: string): {string: any}, string
   local incoming = request as Request
   local params = incoming.GET
   if type(params) ~= "table" then
      local empty: {string: any} = {}
      params = empty
   end
   local filters, err = search.read(params as {string: any})
   if err ~= "" then
      return { status = 400, content_type = "text/plain; charset=utf-8", layout = false }, err
   end
   local settings = config.get()
   local replies = database.pipeline({
      search.command(settings.redis.index, filters),
      { "JSON.GET", settings.redis.catalog_key },
   })
   local documents, total = search.documents(replies[1])
   local catalog = catalog_of(replies[2])
   local host = origin(incoming)
   local base = text(catalog.base_url)
   if base == "" then
      base = host
   end
   local files = directory_map(settings.file_dirs)
   local images = directory_map(settings.image_dirs)
   local self_href = host .. (ngx.var.request_uri or prefix)
   local updated = ""
   for _, document in ipairs(documents) do
      local stamp = text(object(document).updated)
      if stamp > updated then
         updated = stamp
      end
   end
   if updated == "" then
      updated = os.date("!%Y-%m-%dT%H:%M:%SZ") or ""
   end
   local parts: {string} = {}
   add(parts, '<?xml version="1.0" encoding="UTF-8"?>')
   add(parts, '<feed xmlns="' .. ATOM .. '" xmlns:dc="' .. DC .. '" xmlns:opds="' .. OPDS .. '" xmlns:opensearch="' .. OPENSEARCH .. '">')
   element(parts, "id", self_href)
   element(parts, "title", title)
   element(parts, "updated", updated)
   add(parts, "<author>")
   element(parts, "name", text(catalog.author_name))
   element(parts, "uri", text(catalog.author_uri))
   element(parts, "email", text(catalog.author_email))
   add(parts, "</author>")
   add(parts, '<link rel="self" type="' .. ACQUISITION_TYPE .. '" href="' .. escape(self_href) .. '"/>')
   element(parts, "opensearch:totalResults", tostring(total))
   element(parts, "opensearch:startIndex", tostring(filters.start_index))
   element(parts, "opensearch:itemsPerPage", tostring(filters.count))
   for _, document in ipairs(documents) do
      entry(parts, document, base, files, images)
   end
   add(parts, "</feed>")
   return {
      content_type = ACQUISITION_TYPE,
      layout = false,
   }, table.concat(parts)
end

return {
   render = render,
}
