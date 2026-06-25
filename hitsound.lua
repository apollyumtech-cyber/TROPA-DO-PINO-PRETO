-- TROPA DO PINO PRETO - Hitsound/Killsound standalone
-- Load this as a SEPARATE lua in Aimware

local ffi = rawget(_G, "ffi")
if not ffi then print("[TPP Sound] FFI not available"); return end

-- Sound scanning
local soundDir = ".\\csgo\\sounds"
pcall(function()
    pcall(function() ffi.cdef[[ void* GetModuleHandleA(const char*); void* GetProcAddress(void*, const char*); ]] end)
    pcall(function() ffi.cdef[[ typedef struct { uint32_t attr; uint8_t pad[40]; char nm[260]; char alt[14]; } TPP_SND_FD; ]] end)
    local function P(nm, t)
        local h = ffi.C.GetModuleHandleA("kernel32.dll"); if h == nil then return nil end
        local p = ffi.C.GetProcAddress(h, nm); return (p ~= nil) and ffi.cast(t, p) or nil
    end
    local GCD = P("GetCurrentDirectoryA", "uint32_t(*)(uint32_t, char*)")
    if GCD then
        local eb = ffi.new("char[?]", 1024)
        local cwd = ffi.string(eb, GCD(1024, eb))
        soundDir = cwd:gsub("[\\/]bin[\\/]win64.*$", "\\csgo\\sounds")
    end
end)

local function scanSounds()
    local names, paths = {}, {}
    pcall(function()
        local function P(nm, t)
            local h = ffi.C.GetModuleHandleA("kernel32.dll"); if h == nil then return nil end
            local p = ffi.C.GetProcAddress(h, nm); return (p ~= nil) and ffi.cast(t, p) or nil
        end
        local FFF = P("FindFirstFileA", "void*(*)(const char*, void*)")
        local FNF = P("FindNextFileA", "int(*)(void*, void*)")
        local FCL = P("FindClose", "int(*)(void*)")
        if not (FFF and FNF and FCL) then return end
        local INVALID = ffi.cast("void*", ffi.cast("intptr_t", -1))
        local fd = ffi.new("TPP_SND_FD")
        local h = FFF(soundDir .. "\\*.vsnd_c", fd)
        if h ~= INVALID then
            repeat
                local nm = ffi.string(fd.nm)
                if nm:sub(-7):lower() == ".vsnd_c" then
                    local stem = nm:sub(1, #nm - 7)
                    names[#names + 1] = stem
                    paths[#paths + 1] = stem
                end
            until FNF(h, fd) == 0
            FCL(h)
        end
    end)
    table.sort(names)
    if #names == 0 then names[1] = "[ put .vsnd_c in csgo\\sounds ]"; paths[1] = "" end
    return names, paths
end

local SND_NAMES, SND_PATHS = scanSounds()

-- GUI
local Window = gui.Window("tpp_sound", "TPP Hitsound", 100, 300, 300, 320)

local hsEnable = gui.Checkbox(Window, "tpp_hs_on", "Hitsound", true)
local hsCombo = gui.Combobox(Window, "tpp_hs_snd", "Hit Sound", unpack(SND_NAMES))
local hsVol = gui.Slider(Window, "tpp_hs_vol", "Hit Volume", 100, 0, 100, 1)

local ksEnable = gui.Checkbox(Window, "tpp_ks_on", "Killsound", true)
local ksCombo = gui.Combobox(Window, "tpp_ks_snd", "Kill Sound", unpack(SND_NAMES))
local ksVol = gui.Slider(Window, "tpp_ks_vol", "Kill Volume", 100, 0, 100, 1)

-- Sound queue
local sndQueue = {}

local function playSound(idx, vol)
    local path = SND_PATHS[idx + 1]
    if not path or path == "" then return end
    vol = (tonumber(vol) or 100) / 100
    if vol <= 0 then return end
    sndQueue[#sndQueue + 1] = { path = path, vol = vol }
end

-- Event handling
local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local bit_ = rawget(_G, "bit")
local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift

local off_entlist, off_ctrl
pcall(function()
    local cb = mem.GetModuleBase("client.dll")
    -- Resolve sigs
    local function sig_rva(mod, pattern, instrLen)
        local a = mem.FindPattern(mod, pattern); if not a or a == 0 then return nil end
        a = tonumber(a)
        local rel = ffi.cast("int32_t*", a + 3)[0]
        return (a + instrLen + rel) - cb
    end
    off_entlist = sig_rva("client.dll", "48 89 0D ?? ?? ?? ?? E9 ?? ?? ?? ?? CC", 7)
    off_ctrl = sig_rva("client.dll", "48 8B 05 ?? ?? ?? ?? 41 89 BE", 7)
end)

local function getLocal()
    if not (band and off_ctrl and off_entlist) then return nil, nil end
    local base = mem.GetModuleBase("client.dll"); if not base then return nil, nil end
    local lctrl = r_ptr(base + off_ctrl)
    local elist = r_ptr(base + off_entlist)
    if valid(lctrl) and valid(elist) then return lctrl, elist end
    return nil, nil
end

local function slot(elist, idx)
    if not valid(elist) then return nil end
    local chunk = r_ptr(elist + 8 * rshift(idx, 9) + 16); if not valid(chunk) then return nil end
    local e = r_ptr(chunk + 112 * band(idx, 0x1FF))
    if valid(e) and valid(r_ptr(e)) then return e end
    return nil
end

-- Events
pcall(function() client.AllowListener("player_hurt") end)

callbacks.Register("FireGameEvent", "TPP_HitSound_Events", function(ev)
    if not ev then return end
    local name
    pcall(function() name = ev:GetName() end)
    if name ~= "player_hurt" then return end

    local attacker, userid, health, dmg
    pcall(function()
        attacker = ev:GetInt("attacker")
        userid = ev:GetInt("userid")
        health = ev:GetInt("health")
        dmg = ev:GetInt("dmg_health")
    end)
    if not dmg or dmg <= 0 then return end
    if userid == attacker then return end

    local lctrl, elist = getLocal()
    if not lctrl then return end

    local isMe = slot(elist, (attacker or -1) + 1) == lctrl
    if not isMe then return end

    local dead = (health or 1) <= 0
    if dead then
        if ksEnable:GetValue() then
            playSound(ksCombo:GetValue(), ksVol:GetValue())
        end
    else
        if hsEnable:GetValue() then
            playSound(hsCombo:GetValue(), hsVol:GetValue())
        end
    end
end)

-- Flush sounds in Draw (reliable)
callbacks.Register("Draw", "TPP_HitSound_Flush", function()
    if #sndQueue == 0 then return end
    for _, s in ipairs(sndQueue) do
        pcall(function() client.SetConVar("snd_toolvolume", s.vol, true) end)
        pcall(function() client.Command("play sounds\\" .. s.path, true) end)
    end
    sndQueue = {}
end)

-- Window visibility (close with menu, simple approach)
local _menuRef = gui.Reference("Menu")
callbacks.Register("Draw", "TPP_HitSound_UI", function()
    pcall(function() Window:SetInvisible(not _menuRef:IsActive()) end)
end)

print("[TPP Sound] Loaded - " .. #SND_PATHS .. " sounds found")
