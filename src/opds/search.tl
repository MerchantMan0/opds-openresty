local cjson = require("cjson")

local record Filters
   q: string
   author: string
   title: string
   contributor: string
   language: string
   category: string
   publisher: string
   sort: string
   start_index: integer
   count: integer
end

local function pieces(value: string): {string}
   local found: {string} = {}
   for piece in value:gmatch("[^%s%p]+") do
      if piece ~= "" then
         table.insert(found, piece)
      end
   end
   return found
end

local function tag_escape(value: string): string
   return (value:gsub("([,%.<>{}%[%]\"':;!@#%$%%%^&%*%(%)%-%+=~|\\ ])", "\\%1"))
end

local function tokens(field: string, value: string): string
   local words = pieces(value)
   if #words == 0 then
      return ""
   end
   return "@" .. field .. ":(" .. table.concat(words, " ") .. ")"
end

local function text_query(value: string): string
   local parts: {string} = {}
   for _, token in ipairs(pieces(value)) do
      table.insert(parts, "(@title_text:" .. token .. " | @summary:" .. token .. " | @author_text:" .. token .. " | @contributor_text:" .. token .. ")")
   end
   return table.concat(parts, " ")
end

local function exact(field: string, value: string): string
   if value == "" then
      return ""
   end
   return "@" .. field .. ":{" .. tag_escape(value) .. "}"
end

local function query(filters: Filters): string
   local parts: {string} = {}
   local function add(clause: string)
      if clause ~= "" then
         table.insert(parts, clause)
      end
   end
   add(text_query(filters.q))
   add(tokens("author", filters.author))
   add(tokens("title", filters.title))
   add(tokens("contributor", filters.contributor))
   add(exact("language", filters.language))
   add(exact("category", filters.category))
   add(exact("publisher", filters.publisher))
   if filters.sort == "new" then
      add("(@issued_ts:[(0 +inf] | @published_ts:[(0 +inf])")
   end
   if #parts == 0 then
      return "*"
   end
   return table.concat(parts, " ")
end

local function sort_field(filters: Filters): string, string
   if filters.sort == "title" then
      return "title", "ASC"
   end
   if filters.sort == "new" then
      return "issued_ts", "DESC"
   end
   return "updated_ts", "DESC"
end

local function command(index: string, filters: Filters): {string}
   local field, direction = sort_field(filters)
   return {
      "FT.SEARCH", index, query(filters),
      "SORTBY", field, direction,
      "LIMIT", tostring(filters.start_index - 1), tostring(filters.count),
      "RETURN", "1", "$",
      "DIALECT", "2",
   }
end

local function text_field(params: {string: any}, name: string): string, string
   local value = params[name]
   if value == nil then
      return "", ""
   end
   if type(value) ~= "string" then
      return "", name .. " accepts one value"
   end
   return value as string, ""
end

local function whole(params: {string: any}, name: string, default: integer, maximum: integer): integer, string
   local value, err = text_field(params, name)
   if err ~= "" then
      return default, err
   end
   if value == "" then
      return default, ""
   end
   if not value:match("^%d+$") then
      return default, name .. " must be an integer"
   end
   local number = tonumber(value) or 0
   if number < 1 or number > maximum then
      return default, name .. " is out of range"
   end
   return number as integer, ""
end

local function read(params: {string: any}): Filters, string
   local q, q_err = text_field(params, "q")
   local author, author_err = text_field(params, "author")
   local title, title_err = text_field(params, "title")
   local contributor, contributor_err = text_field(params, "contributor")
   local language, language_err = text_field(params, "language")
   local category, category_err = text_field(params, "category")
   local publisher, publisher_err = text_field(params, "publisher")
   local sort, sort_err = text_field(params, "sort")
   local start_index, start_err = whole(params, "startIndex", 1, 10000)
   local count, count_err = whole(params, "count", 20, 100)
   local err = q_err
   if err == "" then err = author_err end
   if err == "" then err = title_err end
   if err == "" then err = contributor_err end
   if err == "" then err = language_err end
   if err == "" then err = category_err end
   if err == "" then err = publisher_err end
   if err == "" then err = sort_err end
   if err == "" and sort ~= "" and sort ~= "new" and sort ~= "updated" and sort ~= "title" then
      err = "sort must be new, updated, or title"
   end
   if err == "" then err = start_err end
   if err == "" then err = count_err end
   return {
      q = q,
      author = author,
      title = title,
      contributor = contributor,
      language = language,
      category = category,
      publisher = publisher,
      sort = sort,
      start_index = start_index,
      count = count,
   }, err
end

local function payload(fields: any): string
   if type(fields) ~= "table" then
      return ""
   end
   local values = fields as {any}
   local index = 1
   while index <= #values do
      if values[index] == "$" and type(values[index + 1]) == "string" then
         return values[index + 1] as string
      end
      index = index + 2
   end
   return ""
end

local function documents(reply: any): {any}, integer
   if type(reply) ~= "table" then
      error("redis reply is not a list")
   end
   local rows = reply as {any}
   local total = tonumber(rows[1]) or 0
   local found: {any} = {}
   local index = 2
   while index <= #rows do
      local body = payload(rows[index + 1])
      if body ~= "" then
         table.insert(found, cjson.decode(body) as any)
      end
      index = index + 2
   end
   return found, total as integer
end

return {
   command = command,
   documents = documents,
   read = read,
}
