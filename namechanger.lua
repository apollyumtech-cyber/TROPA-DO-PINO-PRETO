-- TROPA DO PINO PRETO - Name Changer Solo
-- Exact copy of NC block from femboytap original

local ffi = rawget(_G, "ffi")

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

-- Declare FFI functions (same as VM block does in main script)
pcall(function() ffi.cdef [[
    void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
    int   VirtualProtect(void*, size_t, uint32_t, uint32_t*);
    void* GetCurrentProcess(void);
    int   FlushInstructionCache(void*, void*, size_t);
    void* GetModuleHandleA(const char*);
    void* GetProcAddress(void*, const char*);
]] end)

local NC = { ok = false, installed = false, enabled = false }
do
    local f = ffi
    local DLL  = "engine2.dll"
    local SIG_SETINFO = "40 55 41 57 48 8D 6C 24 ?? 48 81 EC ?? ?? ?? ?? 45 33 FF"
    local STEAL = 16
    local NAME_OFF, KEY_OFF, VAL_OFF = 0x440, 0x8, 0x10

    local T, orig, keepCb

    local function w_u8(a, v)  f.cast("uint8_t*",  a)[0] = v end
    local function w_i32(a, v) f.cast("int32_t*",  a)[0] = v end
    local function le64(a, v)  f.cast("uint64_t*", a)[0] = f.cast("uint64_t", v) end

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
        if type(f) ~= "table" then print("[TPP NC] namechanger: no ffi"); return false end
        -- Warm up mem.FindPattern (same as main script does with VM block)
        pcall(function() mem.FindPattern("client.dll", "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0") end)
        local a = mem.FindPattern(DLL, SIG_SETINFO)
        if not a or a == 0 then print("[TPP NC] namechanger: sig not found"); return false end
        T = a
        local b0 = f.cast("uint8_t*", T)
        local p = alloc_near(T); if p == nil then print("[TPP NC] namechanger: alloc failed"); return false end
        local TR = tonumber(f.cast("uintptr_t", p))

        local saved = {}
        for i = 0, STEAL - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end
        w_u8(TR + STEAL, 0xFF); w_u8(TR + STEAL + 1, 0x25); w_i32(TR + STEAL + 2, 0)
        le64(TR + STEAL + 6, T + STEAL)

        orig = f.cast("char (*)(void*, void*)", f.cast("void*", TR))
        keepCb = f.cast("char (*)(void*, void*)", onSetInfo)

        local old = f.new("uint32_t[1]")
        if f.C.VirtualProtect(f.cast("void*", T), STEAL, 0x40, old) == 0 then
            print("[TPP NC] namechanger: protect failed"); return false
        end
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
    local VT_FIND, FLAGS_OFF    = 0x58, 0x30
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
        local cvar = r_ptr(base + CVAR_RVA);  if not valid(cvar) then return false end
        local vt   = r_ptr(cvar);             if not valid(vt)   then return false end
        local findAddr = r_ptr(vt + VT_FIND); if not valid(findAddr) then return false end
        local findfn  = f.cast("uint64_t (*)(void*, void*, const char*, int)", findAddr)
        local resolve = f.cast("void* (*)(void*, uint32_t, int16_t)", base + RESOLVE_RVA)
        local nameC   = f.new("char[5]", "name")
        local outbuf  = f.new("uint8_t[64]")
        local res     = f.new("uint64_t[4]")
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
    if okI then print("[TPP NC] namechanger: hooked SetInfo @ " .. string.format("%X", T))
    else        print("[TPP NC] namechanger: install failed") end
end
pcall(function() callbacks.Register("Unload", function() pcall(NC.uninstall) end) end)

-- Simple GUI
local Window = gui.Window("tpp_nc", "TPP Name Changer", 420, 100, 300, 260)
local ncEnable = gui.Checkbox(Window, "tpp_nc_on", "Enabled", false)
local ncText = gui.Editbox(Window, "tpp_nc_text", "Name")

local lastApplied = ""
local lastTrigger = 0
local _menuRef = gui.Reference("Menu")

callbacks.Register("Draw", "TPP_NC_Draw", function()
    pcall(function() Window:SetInvisible(not _menuRef:IsActive()) end)

    if not ncEnable:GetValue() then
        NC.enabled = false
        return
    end
    if not NC.ok then return end
    NC.enabled = true

    local name = ncText:GetValue() or ""
    if name == "" then return end

    if name ~= lastApplied then
        lastApplied = name
        NC.setName(name)
    end

    local t = 0
    pcall(function() t = globals.RealTime() end)
    if (t - lastTrigger) >= 0.25 then
        lastTrigger = t
        pcall(NC.fixFlags)
        pcall(function() client.Command('setinfo name "' .. name:gsub('"', '') .. '"', true) end)
    end
end)

print("[TPP NC] loaded" .. (NC.ok and " - ready" or " - FAILED"))
