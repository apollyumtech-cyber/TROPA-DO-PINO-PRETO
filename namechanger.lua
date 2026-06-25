-- TROPA DO PINO PRETO - Name Changer Standalone
-- Includes all dependencies in correct order

local ffi = rawget(_G, "ffi")
if not ffi then print("[TPP NC] no ffi"); return end

local floor = math.floor
local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

-- Step 1: ffi.cdef (same as VM block declares)
pcall(function() ffi.cdef [[
    void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
    int   VirtualProtect(void*, size_t, uint32_t, uint32_t*);
    void* GetCurrentProcess(void);
    int   FlushInstructionCache(void*, void*, size_t);
]] end)

-- Step 2: ffi.cdef (same as HS block declares)
pcall(function() ffi.cdef [[ void* GetModuleHandleA(const char*); void* GetProcAddress(void*, const char*); ]] end)

-- Step 3: Load changer (provides C.offsets needed by localInfo)
local BASE = "https://raw.githubusercontent.com/apollyumtech-cyber/TROPA-DO-PINO-PRETO/main/"
local function fetch(url)
    local src
    pcall(function() src = http.Get(url .. "?nocache=" .. tostring({}):gsub("%W", "")) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    return src
end

local C
do
    local src = fetch(BASE .. "tropado_pino_preto_changer.lua")
    if src then
        local chunk = loadstring(src, "=changer.lua")
        if chunk then
            local ok, mod = pcall(chunk)
            if ok and type(mod) == "table" then C = mod end
        end
    end
end
if not C then print("[TPP NC] changer failed"); return end
print("[TPP NC] changer OK, offsets: entlist=" .. tostring(C.offsets and C.offsets.dwEntityList) .. " ctrl=" .. tostring(C.offsets and C.offsets.dwLocalPlayerController))

-- Step 4: Minimal HS.localInfo (detects in-game state)
local HS = {}
do
    local bit_ = rawget(_G, "bit")
    local DLL = "client.dll"
    local off = {}
    off.dwEntityList = C.offsets and C.offsets.dwEntityList
    off.dwLocalPlayerController = C.offsets and C.offsets.dwLocalPlayerController

    local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift

    function HS.localInfo()
        if not (type(ffi) == "table" and band and off.dwLocalPlayerController and off.dwEntityList) then return nil, nil end
        local base = mem.GetModuleBase(DLL); if not base then return nil, nil end
        local lctrl = r_ptr(base + off.dwLocalPlayerController)
        local elist = r_ptr(base + off.dwEntityList)
        if valid(lctrl) and valid(elist) then return lctrl, elist end
        return nil, nil
    end
end

-- Step 4.5: Trigger mem.FindPattern on client.dll first (same as VM block does)
-- This may be required to initialize Aimware's pattern scanner for other modules
pcall(function()
    local SIG_VM = "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0"
    mem.FindPattern("client.dll", SIG_VM)
end)

-- Step 5: NC block (exact copy from original)
local NC = { ok = false, installed = false, enabled = false }
do
    local f = ffi
    local DLL = "engine2.dll"
    local SIG_SETINFO = "40 55 41 57 48 8D 6C 24 ?? 48 81 EC ?? ?? ?? ?? 45 33 FF"
    local STEAL = 16
    local NAME_OFF, KEY_OFF, VAL_OFF = 0x440, 0x8, 0x10

    local T, orig, keepCb

    local function w_u8(a, v) f.cast("uint8_t*", a)[0] = v end
    local function w_i32(a, v) f.cast("int32_t*", a)[0] = v end
    local function le64(a, v) f.cast("uint64_t*", a)[0] = f.cast("uint64_t", v) end

    local function alloc_near(target)
        local gran = 0x10000
        local b = target - (target % gran)
        for i = 1, 0x8000 do
            local lo = b - i * gran
            if lo > 0x10000 then
                local p = f.C.VirtualAlloc(f.cast("void*", lo), 64, 0x3000, 0x40)
                if p ~= nil then return p end
            end
            local p2 = f.C.VirtualAlloc(f.cast("void*", b + i * gran), 64, 0x3000, 0x40)
            if p2 ~= nil then return p2 end
        end
        return nil
    end

    function NC.setName(s)
        s = tostring(s or "")
        if #s == 0 then NC._buf = nil; return end
        NC._buf = f.new("char[?]", #s + 1, s)
    end

    local function onSetInfo(rcx, a2)
        if NC.enabled and NC._buf ~= nil and a2 ~= nil then
            pcall(function()
                local a2n = tonumber(f.cast("uintptr_t", a2))
                if a2n and a2n >= 0x1000 then
                    local arg_list = r_ptr(a2n + NAME_OFF)
                    if arg_list and arg_list >= 0x1000 then
                        local key = r_ptr(arg_list + KEY_OFF)
                        if valid(key) then
                            local ks = f.string(f.cast("const char*", key))
                            if ks:lower() == "name" then
                                f.cast("const char**", arg_list + VAL_OFF)[0] = f.cast("const char*", NC._buf)
                            end
                        end
                    end
                end
            end)
        end
        return orig(rcx, a2)
    end

    local function install()
        if type(f) ~= "table" then return false end
        local a = mem.FindPattern(DLL, SIG_SETINFO)
        if not a or a == 0 then print("[TPP NC] sig not found"); return false end
        T = a
        local b0 = f.cast("uint8_t*", T)
        local p = alloc_near(T); if p == nil then print("[TPP NC] alloc failed"); return false end
        local TR = tonumber(f.cast("uintptr_t", p))

        local saved = {}
        for i = 0, STEAL - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end
        w_u8(TR + STEAL, 0xFF); w_u8(TR + STEAL + 1, 0x25); w_i32(TR + STEAL + 2, 0)
        le64(TR + STEAL + 6, T + STEAL)

        orig = f.cast("char (*)(void*, void*)", f.cast("void*", TR))
        keepCb = f.cast("char (*)(void*, void*)", onSetInfo)

        local old = f.new("uint32_t[1]")
        if f.C.VirtualProtect(f.cast("void*", T), STEAL, 0x40, old) == 0 then return false end
        w_u8(T, 0xFF); w_u8(T + 1, 0x25); w_i32(T + 2, 0)
        le64(T + 6, tonumber(f.cast("uintptr_t", keepCb)))
        for i = 14, STEAL - 1 do w_u8(T + i, 0x90) end
        f.C.VirtualProtect(f.cast("void*", T), STEAL, old[0], old)
        pcall(function() f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", T), STEAL) end)

        NC._saved = saved
        NC.installed = true
        return true
    end

    function NC.uninstall()
        if not (NC.installed and T and NC._saved) then return end
        pcall(function()
            local old = f.new("uint32_t[1]")
            f.C.VirtualProtect(f.cast("void*", T), STEAL, 0x40, old)
            for i = 0, STEAL - 1 do w_u8(T + i, NC._saved[i]) end
            f.C.VirtualProtect(f.cast("void*", T), STEAL, old[0], old)
            f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", T), STEAL)
        end)
        NC.installed = false
    end

    local CVAR_RVA, RESOLVE_RVA = 0x685698, 0x3FC080
    local VT_FIND, FLAGS_OFF = 0x58, 0x30
    local F_USERINFO, F_PROTECTED = 0x200, 0x2
    local bit_ = rawget(_G, "bit")

    function NC.fixFlags()
        if type(f) ~= "table" or not bit_ then return false end
        if NC._flags then
            local p = f.cast("uint32_t*", NC._flags)
            p[0] = bit_.band(bit_.bor(p[0], F_USERINFO), bit_.bnot(F_PROTECTED))
            return true
        end
        local base = mem.GetModuleBase(DLL); if not base then return false end
        local cvar = r_ptr(base + CVAR_RVA); if not valid(cvar) then return false end
        local vt = r_ptr(cvar); if not valid(vt) then return false end
        local findAddr = r_ptr(vt + VT_FIND); if not valid(findAddr) then return false end
        local findfn = f.cast("uint64_t (*)(void*, void*, const char*, int)", findAddr)
        local resolve = f.cast("void* (*)(void*, uint32_t, int16_t)", base + RESOLVE_RVA)
        local nameC = f.new("char[5]", "name")
        local outbuf = f.new("uint8_t[64]")
        local res = f.new("uint64_t[4]")
        local done = false
        pcall(function()
            local ref = tonumber(findfn(f.cast("void*", cvar), outbuf, nameC, 1))
            if not ref or ref < 0x10000 then return end
            local handle = f.cast("uint32_t*", ref)[0]
            resolve(res, handle, -1)
            local obj = tonumber(res[1])
            if not valid(obj) then return end
            NC._flags = obj + FLAGS_OFF
            local p = f.cast("uint32_t*", NC._flags)
            p[0] = bit_.band(bit_.bor(p[0], F_USERINFO), bit_.bnot(F_PROTECTED))
            done = true
        end)
        return done
    end

    local okI = false
    pcall(function() okI = install() end)
    NC.ok = okI
    if okI then print("[TPP NC] hooked @ " .. string.format("%X", T))
    else print("[TPP NC] hook failed") end
end
pcall(function() callbacks.Register("Unload", function() pcall(NC.uninstall) end) end)

-- Step 6: GUI + Logic
local Window = gui.Window("tpp_nc", "TPP Name Changer", 420, 100, 300, 280)
local ncEnable = gui.Checkbox(Window, "tpp_nc_on", "Enabled", false)
local ncMode = gui.Combobox(Window, "tpp_nc_mode", "Mode", "Full name", "Clantag")
local ncSource = gui.Combobox(Window, "tpp_nc_src", "Source", "Static", "TROPA", "Aimware", "Custom")
local ncText = gui.Editbox(Window, "tpp_nc_text", "Text")
local ncSpeed = gui.Slider(Window, "tpp_nc_speed", "Speed", 400, 100, 1500, 10)

local TROPA_SEQ = {
    { t = "", ms = 550 },
    { t = "$T", ms = 80 }, { t = "$TR", ms = 80 }, { t = "$TRO", ms = 80 },
    { t = "$TROP", ms = 80 }, { t = "$TROPA", ms = 80 }, { t = "$TROPA$", ms = 2000 },
    { t = "$TROP", ms = 60 }, { t = "$TRO", ms = 60 }, { t = "$TR", ms = 60 },
    { t = "$T", ms = 60 }, { t = "", ms = 300 },
}
local AIM_SEQ = {
    { t = "", ms = 450 },
    { t = "[A]", ms = 120 }, { t = "[AI]", ms = 120 }, { t = "[AIM]", ms = 120 },
    { t = "[AIMW]", ms = 120 }, { t = "[AIMWA]", ms = 120 }, { t = "[AIMWAR]", ms = 120 },
    { t = "[AIMWARE]", ms = 110 }, { t = "[AIMWARE.]", ms = 120 }, { t = "[AIMWARE.N]", ms = 90 },
    { t = "[AIMWARE.NE]", ms = 120 }, { t = "[AIMWARE.NET]", ms = 2000 },
    { t = "[AIMWARE.NE]", ms = 120 }, { t = "[AIMWARE.N]", ms = 120 },
    { t = "[AIMWARE.]", ms = 120 }, { t = "[AIMWARE]", ms = 120 }, { t = "[AIMWAR]", ms = 120 },
    { t = "[AIMWA]", ms = 120 }, { t = "[AIMW]", ms = 120 }, { t = "[AIM]", ms = 120 },
    { t = "[AI]", ms = 120 }, { t = "[A]", ms = 120 },
}

local function frameAt(seq, t, factor)
    local n = #seq; if n == 0 then return "" end
    local total = 0
    for i = 1, n do total = total + seq[i].ms * factor end
    if total <= 0 then return seq[1].t end
    local ms = (t * 1000) % total
    local acc = 0
    for i = 1, n do
        acc = acc + seq[i].ms * factor
        if ms < acc then return seq[i].t end
    end
    return seq[n].t
end

local function getFrame(t)
    local src = ncSource:GetValue()
    local speed = ncSpeed:GetValue() / 400
    if src == 0 then return ncText:GetValue() or ""
    elseif src == 1 then return frameAt(TROPA_SEQ, t, speed)
    elseif src == 2 then return frameAt(AIM_SEQ, t, speed)
    else return frameAt({{ t = ncText:GetValue() or "", ms = 2000 }}, t, speed)
    end
end

local lastApplied = ""
local lastTrigger = 0
local _menuRef = gui.Reference("Menu")

callbacks.Register("Draw", "TPP_NC_Draw", function()
    pcall(function() Window:SetInvisible(not _menuRef:IsActive()) end)

    if not ncEnable:GetValue() then NC.enabled = false; return end
    if not NC.ok then return end
    NC.enabled = true

    local t = 0
    pcall(function() t = globals.RealTime() end)

    local name = getFrame(t)
    if name == "" then return end

    if name ~= lastApplied then
        lastApplied = name
        NC.setName(name)
    end

    if (t - lastTrigger) >= 0.25 then
        lastTrigger = t
        pcall(NC.fixFlags)
        pcall(function() client.Command('setinfo name "' .. name:gsub('"', '') .. '"', true) end)
    end
end)

print("[TPP NC] standalone loaded" .. (NC.ok and " - READY" or " - FAILED"))
