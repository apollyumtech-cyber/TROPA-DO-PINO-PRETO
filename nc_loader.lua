-- TPP Name Changer Loader
local src
pcall(function() src = http.Get("https://raw.githubusercontent.com/apollyumtech-cyber/TROPA-DO-PINO-PRETO/main/namechanger.lua?nocache=" .. tostring({}):gsub("%W", "")) end)
if type(src) ~= "string" or #src < 100 then pcall(function() src = http.Get("https://raw.githubusercontent.com/apollyumtech-cyber/TROPA-DO-PINO-PRETO/main/namechanger.lua") end) end
if type(src) ~= "string" then print("[TPP NC] cannot fetch"); return end
local chunk, err = loadstring(src, "=namechanger.lua")
if not chunk then print("[TPP NC] compile: " .. tostring(err)); return end
local ok, e = pcall(chunk)
if not ok then print("[TPP NC] error: " .. tostring(e)) end
