-- TROPA DO PINO PRETO - Name Changer standalone
-- Load this as a SEPARATE lua in Aimware

local ffi = rawget(_G, "ffi")
if not ffi then print("[TPP NC] FFI not available"); return end

-- GUI
local Window = gui.Window("tpp_nc", "TPP Name Changer", 420, 100, 320, 380)

local ncEnable = gui.Checkbox(Window, "tpp_nc_on", "Enabled", false)
local ncMode = gui.Combobox(Window, "tpp_nc_mode", "Mode", "Full name", "Clantag")
local ncSource = gui.Combobox(Window, "tpp_nc_src", "Source", "Static", "TROPA", "Aimware", "Custom")
local ncStyle = gui.Combobox(Window, "tpp_nc_style", "Style", "Typing", "Glitch")
local ncText = gui.Editbox(Window, "tpp_nc_text", "Custom text")
local ncSpeed = gui.Slider(Window, "tpp_nc_speed", "Frame ms", 400, 100, 1500, 10)

-- Name changer hook
local NC = { ok = false, enabled = false }
local DLL = "engine2.dll"
local SIG_SETINFO = "40 55 41 57 48 8D 6C 24 ?? 48 81 EC ?? ?? ?? ?? 45 33 FF"
local STEAL = 16
local NAME_OFF, KEY_OFF, VAL_OFF = 0x440, 0x8, 0x10

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local function w_u8(a, v) ffi.cast("uint8_t*", a)[0] = v end
local function w_i32(a, v) ffi.cast("int32_t*", a)[0] = v end
local function le64(a, v) ffi.cast("uint64_t*", a)[0] = ffi.cast("uint64_t", v) end

function NC.setName(s)
    s = tostring(s or "")
    if #s == 0 then NC._buf = nil; return end
    NC._buf = ffi.new("char[?]", #s + 1, s)
end

local orig

local function alloc_near(target)
    local gran = 0x10000
    local b = target - (target % gran)
    for i = 1, 0x8000 do
        local lo = b - i * gran
        if lo > 0x10000 then
            local p = ffi.C.VirtualAlloc(ffi.cast("void*", lo), 64, 0x3000, 0x40)
            if p ~= nil then return p end
        end
        local p2 = ffi.C.VirtualAlloc(ffi.cast("void*", b + i * gran), 64, 0x3000, 0x40)
        if p2 ~= nil then return p2 end
    end
    return nil
end

local function install()
    pcall(function() ffi.cdef[[
        void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
        int VirtualProtect(void*, size_t, uint32_t, uint32_t*);
        void* GetCurrentProcess(void);
        int FlushInstructionCache(void*, void*, size_t);
    ]] end)

    local a = mem.FindPattern(DLL, SIG_SETINFO)
    if not a or a == 0 then print("[TPP NC] sig not found"); return false end
    local T = tonumber(a)
    local b0 = ffi.cast("uint8_t*", T)
    local p = alloc_near(T)
    if p == nil then print("[TPP NC] alloc failed"); return false end
    local TR = tonumber(ffi.cast("uintptr_t", p))

    local saved = {}
    for i = 0, STEAL - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end
    w_u8(TR + STEAL, 0xFF); w_u8(TR + STEAL + 1, 0x25); w_i32(TR + STEAL + 2, 0)
    le64(TR + STEAL + 6, T + STEAL)

    orig = ffi.cast("int(*)(void*, void*)", ffi.cast("void*", TR))

    local keepCb
    keepCb = ffi.cast("int(*)(void*, void*)", function(rcx, a2)
        if NC.enabled and NC._buf ~= nil and a2 ~= nil then
            pcall(function()
                local a2n = tonumber(ffi.cast("uintptr_t", a2))
                if a2n and a2n >= 0x1000 then
                    local arg_list = r_ptr(a2n + NAME_OFF)
                    if arg_list and arg_list >= 0x1000 then
                        local key = r_ptr(arg_list + KEY_OFF)
                        if valid(key) then
                            local ks = ffi.string(ffi.cast("const char*", key))
                            if ks:lower() == "name" then
                                ffi.cast("const char**", arg_list + VAL_OFF)[0] = ffi.cast("const char*", NC._buf)
                            end
                        end
                    end
                end
            end)
        end
        return orig(rcx, a2)
    end)
    NC._keepCb = keepCb

    local old = ffi.new("uint32_t[1]")
    ffi.C.VirtualProtect(ffi.cast("void*", T), STEAL, 0x40, old)
    w_u8(T, 0xFF); w_u8(T + 1, 0x25); w_i32(T + 2, 0)
    le64(T + 6, tonumber(ffi.cast("uintptr_t", keepCb)))
    for i = 14, STEAL - 1 do w_u8(T + i, 0x90) end
    ffi.C.VirtualProtect(ffi.cast("void*", T), STEAL, old[0], old)
    pcall(function() ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), ffi.cast("void*", T), STEAL) end)

    NC.ok = true
    NC._T = T
    NC._saved = saved
    print("[TPP NC] hooked SetInfo @ " .. string.format("%X", T))
    return true
end

pcall(install)

-- Uninstall on unload
pcall(function()
    callbacks.Register("Unload", "TPP_NC_Unload", function()
        if NC.ok and NC._T and NC._saved then
            pcall(function()
                local old = ffi.new("uint32_t[1]")
                ffi.C.VirtualProtect(ffi.cast("void*", NC._T), STEAL, 0x40, old)
                for i = 0, STEAL - 1 do w_u8(NC._T + i, NC._saved[i]) end
                ffi.C.VirtualProtect(ffi.cast("void*", NC._T), STEAL, old[0], old)
            end)
        end
    end)
end)

-- Animation sequences
local TROPA_SEQ = {
    { t = "", ms = 550 },
    { t = "$T", ms = 80 }, { t = "$TR", ms = 80 }, { t = "$TRO", ms = 80 },
    { t = "$TROP", ms = 80 }, { t = "$TROPA", ms = 80 },
    { t = "$TROPA$", ms = 2000 },
    { t = "$TROP", ms = 60 }, { t = "$TRO", ms = 60 },
    { t = "$TR", ms = 60 }, { t = "$T", ms = 60 }, { t = "", ms = 300 },
}

local AIM_SEQ = {
    { t = "", ms = 450 },
    { t = "[A]", ms = 120 }, { t = "[AI]", ms = 120 }, { t = "[AIM]", ms = 120 },
    { t = "[AIMW]", ms = 120 }, { t = "[AIMWA]", ms = 120 },
    { t = "[AIMWAR]", ms = 120 }, { t = "[AIMWARE]", ms = 110 },
    { t = "[AIMWARE.]", ms = 120 }, { t = "[AIMWARE.N]", ms = 90 },
    { t = "[AIMWARE.NE]", ms = 120 }, { t = "[AIMWARE.NET]", ms = 2000 },
    { t = "[AIMWARE.NE]", ms = 120 }, { t = "[AIMWARE.N]", ms = 120 },
    { t = "[AIMWARE.]", ms = 120 }, { t = "[AIMWARE]", ms = 120 },
    { t = "[AIMWAR]", ms = 120 }, { t = "[AIMWA]", ms = 120 },
    { t = "[AIMW]", ms = 120 }, { t = "[AIM]", ms = 120 },
    { t = "[AI]", ms = 120 }, { t = "[A]", ms = 120 },
}

local function glitchSeq(target)
    local LEET = { a={"@","4"}, e={"3"}, i={"1","!"}, o={"0"}, s={"$"}, t={"7"} }
    local function corrupt()
        local chars = {}
        for i = 1, #target do
            local c = target:sub(i, i)
            local alt = LEET[c:lower()]
            if alt and math.random() < 0.4 then c = alt[math.random(#alt)] end
            chars[i] = c
        end
        return table.concat(chars)
    end
    local seq = {}
    for _ = 1, 6 do seq[#seq + 1] = { t = corrupt(), ms = 55 } end
    seq[#seq + 1] = { t = target, ms = 2000 }
    for _ = 1, 6 do seq[#seq + 1] = { t = corrupt(), ms = 55 } end
    seq[#seq + 1] = { t = target, ms = 2000 }
    return seq
end

local function typingSeq(text, ms)
    local seq = { { t = "", ms = 300 } }
    for i = 1, #text do
        seq[#seq + 1] = { t = text:sub(1, i), ms = ms or 100 }
    end
    seq[#seq + 1] = { t = text, ms = 2000 }
    for i = #text - 1, 0, -1 do
        seq[#seq + 1] = { t = text:sub(1, i), ms = 60 }
    end
    return seq
end

local function getSeq()
    local src = ncSource:GetValue()
    local style = ncStyle:GetValue()
    local text = ncText:GetValue() or "TROPA"

    if src == 0 then -- Static
        return { { t = text, ms = 1000 } }
    elseif src == 1 then -- TROPA
        if style == 1 then return glitchSeq("$TROPA$") end
        return TROPA_SEQ
    elseif src == 2 then -- Aimware
        if style == 1 then return glitchSeq("[AIMWARE.NET]") end
        return AIM_SEQ
    else -- Custom
        if style == 1 then return glitchSeq(text) end
        return typingSeq(text, 100)
    end
end

local function frameAt(seq, t, factor)
    factor = factor or 1
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

-- Apply name
local function applyName(name, isClantag)
    if isClantag then
        pcall(function() client.SetConVar("cl_clanid", 0, true) end)
        pcall(function() client.Command('cl_clanid 0; say_team ""', true) end)
    else
        NC.setName(name)
    end
end

-- Main logic
local lastApplied = ""
local function getClock()
    local t = 0
    pcall(function() t = globals.RealTime() end)
    if t == 0 then pcall(function() t = globals.CurTime() end) end
    return t
end

callbacks.Register("Draw", "TPP_NC_Logic", function()
    local menu = gui.Reference("Menu"):IsActive()
    Window:SetInvisible(not menu)

    if not ncEnable:GetValue() then
        NC.enabled = false
        return
    end
    if not NC.ok then return end

    NC.enabled = true
    local mode = ncMode:GetValue() -- 0=fullname, 1=clantag
    local seq = getSeq()
    local speed = ncSpeed:GetValue() / 400
    local t = getClock()
    local name = frameAt(seq, t, speed)

    if name ~= lastApplied then
        lastApplied = name
        NC.setName(name)
        if mode == 0 then
            -- Force engine to send name update (triggers our hook)
            pcall(function() client.Command("name " .. name, true) end)
            pcall(function() client.Command("setinfo name " .. name, true) end)
        else
            -- Clantag mode
            pcall(function() client.Command("cl_clanid 0", true) end)
        end
    end
end)

print("[TPP NC] Name Changer loaded" .. (NC.ok and " - hook OK" or " - hook FAILED"))

-- Window visibility
local _ncMenuRef = gui.Reference("Menu")
callbacks.Register("Draw", "TPP_NC_UI", function()
    pcall(function() Window:SetInvisible(not _ncMenuRef:IsActive()) end)
end)
