local USER    = "apollyumtech-cyber"
local REPO    = "TROPA-DO-PINO-PRETO"
local VERSION = "latest"
local TAG     = "[TROPA DO PINO PRETO] "

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then return "main" end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

-- ========== HWID GENERATION ==========
local function getHWID()
    local hwid = ""
    pcall(function()
        local ffi = ffi or require("ffi")
        pcall(function() ffi.cdef[[
            int GetVolumeInformationA(
                const char*, char*, uint32_t, uint32_t*,
                uint32_t*, uint32_t*, char*, uint32_t
            );
            void GetSystemInfo(void*);
            unsigned int GetCurrentProcessId(void);
        ]] end)

        -- Disk serial
        local serial = ffi.new("uint32_t[1]")
        ffi.C.GetVolumeInformationA("C:\\", nil, 0, serial, nil, nil, nil, 0)
        local diskSerial = tonumber(serial[0]) or 0

        -- Process ID seed (constant per machine via volume)
        local machineID = string.format("%08X", diskSerial)

        -- Simple hash
        local hash = 0x5A3C1E7D
        for i = 1, #machineID do
            hash = bit.bxor(hash, machineID:byte(i) * 0x1000193)
            hash = bit.band(hash, 0xFFFFFFFF)
        end

        hwid = string.format("%08X%08X", diskSerial, hash)
    end)
    return hwid
end

-- ========== AUTH CHECK ==========
local function checkAuth(hwid)
    local authURL = BASE .. "auth.txt"
    local authData = nil
    pcall(function() authData = http.Get(authURL) end)
    if not authData or #authData < 5 then
        pcall(function() authData = http.Get(authURL) end)
    end
    if not authData then
        print(TAG .. "WARNING: Could not fetch auth list, allowing access")
        return true
    end
    for line in authData:gmatch("[^\r\n]+") do
        local clean = line:gsub("%s", ""):gsub("%-%-.*", "")
        if clean ~= "" and clean:upper() == hwid:upper() then
            return true
        end
    end
    return false
end

-- ========== MAIN ==========
local hwid = getHWID()

if hwid == "" or #hwid < 8 then
    print(TAG .. "ERROR: Could not generate HWID")
    return
end

print(TAG .. "Your HWID: " .. hwid)

if not checkAuth(hwid) then
    print(TAG .. "ACCESS DENIED - HWID not authorized")
    print(TAG .. "Send this HWID to admin: " .. hwid)
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
