-- TPP Name Changer Loader
-- Loads changer first (initializes FFI/mem state) then NC
local BASE = "https://raw.githubusercontent.com/apollyumtech-cyber/TROPA-DO-PINO-PRETO/main/"

local function fetch(url)
    local src
    pcall(function() src = http.Get(url .. "?nocache=" .. tostring({}):gsub("%W", "")) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    return src
end

-- Load changer first (initializes FFI state needed for NC)
local csrc = fetch(BASE .. "tropado_pino_preto_changer.lua")
if csrc then
    local chunk = loadstring(csrc, "=changer_init.lua")
    if chunk then pcall(chunk) end
end

-- Now load NC
local src = fetch(BASE .. "namechanger.lua")
if not src then print("[TPP NC] cannot fetch"); return end
local chunk, err = loadstring(src, "=namechanger.lua")
if not chunk then print("[TPP NC] compile: " .. tostring(err)); return end
local ok, e = pcall(chunk)
if not ok then print("[TPP NC] error: " .. tostring(e)) end
