local USER    = "apollyumtech-cyber"
local REPO    = "TROPA-DO-PINO-PRETO"
local VERSION = "latest"

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then return "main" end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then return src, "cache" end
    return nil
end

local src, where = fetch(BASE .. "tropado_pino_preto.lua", ".\\tropado_pino_preto_lua\\tropado_pino_preto.lua")
if not src then print("[TROPA DO PINO PRETO] FATAL: cannot fetch main script") return end

local chunk, err = loadstring(src, "=tropado_pino_preto.lua")
if not chunk then print("[TROPA DO PINO PRETO] compile error: " .. tostring(err)) return end

_G.TROPADO_BASE = BASE
print(string.format("[TROPA DO PINO PRETO] %s from %s", ref(), tostring(where)))

local ok, e = pcall(chunk)
if not ok then print("[TROPA DO PINO PRETO] run error: " .. tostring(e)) end
