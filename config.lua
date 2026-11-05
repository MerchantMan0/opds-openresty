local chunk, err = loadfile("build/config.lua")
if not chunk then
   error("run cyan build before starting Lapis (" .. err .. ")")
end
chunk()
