local USER    = "apollyumtech-cyber"
local REPO    = "TROPA-DO-PINO-PRETO"
local VERSION = "latest"
local TAG     = "[TROPA DO PINO PRETO] "

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then return "main" end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

-- ========== AUTH CHECK ==========
local function getUsername()
    local name = ""
    pcall(function() name = cheat.GetUserName() end)
    return name
end

local function checkAuth(username)
    local authURL = BASE .. "auth.txt"
    local authData = nil
    pcall(function() authData = http.Get(authURL) end)
    if not authData or #authData < 3 then
        pcall(function() authData = http.Get(authURL) end)
    end
    if not authData then
        print(TAG .. "WARNING: Could not fetch auth list, allowing access")
        return true
    end
    for line in authData:gmatch("[^\r\n]+") do
        local clean = line:gsub("%s", ""):gsub("%-%-.*", "")
        if clean ~= "" and clean:lower() == username:lower() then
            return true
        end
    end
    return false
end

-- ========== MAIN ==========
local username = getUsername()

if username == "" then
    print(TAG .. "ERROR: Could not get username")
    return
end

print(TAG .. "User: " .. username)

if not checkAuth(username) then
    print(TAG .. "ACCESS DENIED - User not authorized")
    print(TAG .. "Send this name to admin: " .. username)
    return
end

print(TAG .. "Access granted")

-- ========== LOAD SCRIPT ==========
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
if not src then print(TAG .. "FATAL: cannot fetch main script") return end

local chunk, err = loadstring(src, "=tropado_pino_preto.lua")
if not chunk then print(TAG .. "compile error: " .. tostring(err)) return end

_G.TROPADO_BASE = BASE
print(string.format(TAG .. "%s from %s", ref(), tostring(where)))

local ok, e = pcall(chunk)
if not ok then print(TAG .. "run error: " .. tostring(e)) end
