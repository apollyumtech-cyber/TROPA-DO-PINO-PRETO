local BASE        = rawget(_G, "TROPADO_BASE") or "https://raw.githubusercontent.com/apollyumtech-cyber/TROPA-DO-PINO-PRETO/main/"
local GUILIB_URL  = BASE .. "tropado_pino_preto_guilib.lua"
local CHANGER_URL = BASE .. "tropado_pino_preto_changer.lua"

local ffi = rawget(_G, "ffi")

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local SIG = {
    vm = "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0",
}

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

local function load(url, cacheFile, name)
    local src, where = fetch(url, cacheFile)
    if not src then print("[TROPA DO PINO PRETO] FATAL: cannot load " .. name) return nil end
    local chunk, err = loadstring(src, "=" .. cacheFile)
    if not chunk then print("[TROPA DO PINO PRETO] " .. name .. " compile error: " .. tostring(err)) return nil end
    local ok, mod = pcall(chunk)
    if not ok then print("[TROPA DO PINO PRETO] " .. name .. " run error: " .. tostring(mod)) return nil end
    print("[TROPA DO PINO PRETO] " .. name .. " loaded from " .. tostring(where))
    return mod
end

local M = load(GUILIB_URL, ".\tropado_pino_preto_lua\tropado_pino_preto_guilib.lua", "guilib")
if type(M) ~= "table" then return end

-- ensure theme table is accessible
if not M.T then
    -- try to find it from internal references
    for k, v in pairs(M) do
        if type(v) == "table" and v.accent and v.bg and v.text then
            M.T = v; break
        end
    end
end

local C = load(CHANGER_URL, ".\tropado_pino_preto_lua\tropado_pino_preto_changer.lua", "changer")
if type(C) ~= "table" then return end

local floor = math.floor

local VM = {}
local HS = {}

local weaponLb, skinLb, skinWd
local sWear, sSeed, cbAuto
local modelLb, modelWd, modelPaths
local cbVm, vmX, vmY, vmZ
local hsOn, hsCmb, hsCmbWd, hsVol
local ksOn, ksCmb, ksCmbWd, ksVol
local hlOn, hlMiss, hlHit, hlHurt, hlKill
local wmOn, wmElems, wmPos
local rgOn, rgCmb, rgCmbWd, rgPen, rgMin
local ncOn, ncMode, ncSrc, ncText, ncSpeed
local vrOn, vrMode
local SND_NAMES, SND_PATHS

local lastModelSel = -1
local curPaints    = { 0 }
local lastSel      = -1
local lastSig      = nil
local lastAutoDef  = nil
local lastAuto     = false

-- Forward declarations for category system
local CATEGORIES, catFilteredMap, catCombo, weaponWd, filterByCategory, _lastCat, curCatNames

-- Session Stats and Bomb Timer
local STATS = { kills = 0, deaths = 0, hits = 0, shots = 0, headshots = 0, dmg = 0 }
local BOMB = { planted = false, time = 0, site = "", maxTime = 40 }

-- Spammer forward declarations
local _spamRoundCount = 0
local _spamVacSent = false
local _spamLastServer = nil
local _spamLastTime = 0
local _spamMultiIdx = 1
local spamVac, spamVacRound, spamOn, spamMode, spamText, spamDelay, spamChat

local function item()     return C.items[weaponLb:Get()] end
local function paint()    return curPaints[skinLb:Get()] or 0 end
local function settings() return sWear:Get(), floor(sSeed:Get() + 0.5) end

local function applySelected()
    local it = item(); if not it then return end
    local w, s = settings()
    C.apply(it, paint(), w, s)
end

local function sig()
    local it = item(); if not it then return "none" end
    local w, s = settings()
    return it.def.."|"..paint().."|"..floor(w * 100000).."|"..s
end

local function autoFollow()
    if not cbAuto:Get() then lastAutoDef = nil; return end
    local def = C.activeDef(); if not def then return end
    if not C.defToItem[def] and C.isKnife(def) and C.knifeDef() then def = C.knifeDef() end
    if def == lastAutoDef then return end
    lastAutoDef = def
    -- Find in current category filter
    for localIdx, globalIdx in pairs(catFilteredMap or {}) do
        if C.items[globalIdx] and C.items[globalIdx].def == def then
            weaponLb:Set(localIdx)
            return
        end
    end
    -- If not in current category, find the right category and switch
    local globalIdx = C.defToItem[def]; if not globalIdx then return end
    local it = C.items[globalIdx]; if not it then return end
    for ci, cat in ipairs(CATEGORIES) do
        local match = false
        if cat.filter then match = (it.kind == cat.filter)
        elseif cat.defs then
            for _, d in ipairs(cat.defs) do if d == def then match = true; break end end
        end
        if match then
            catCombo:Set(ci)
            _lastCat = ci
            filterByCategory(ci)
            weaponWd.items = curCatNames
            weaponWd.scroll = 0
            for li, gi in pairs(catFilteredMap) do
                if gi == globalIdx then weaponLb:Set(li); break end
            end
            return
        end
    end
end

local function autoApply()
    local s = sig()
    if s == lastSig then return end
    lastSig = s
    applySelected()
end

local function syncSkins()
    local sel = weaponLb:Get()
    if sel == lastSel then return end
    lastSel = sel
    local it = item(); if not it then return end
    local names, paints = C.skinList(it.def)
    curPaints     = paints
    skinWd.items  = names
    skinWd.value  = 1
    skinWd.scroll = 0
    local c = C.getCfg(it.def)
    if c then
        sWear:Set(c.wear); sSeed:Set(c.seed)
        for i = 2, #paints do
            if paints[i] == c.paint then skinWd.value = i; break end
        end
    end
    lastSig = sig()
end

local function persistOpts()
    local v = cbAuto:Get()
    if v ~= lastAuto then lastAuto = v; C.setOpt("autoFollow", v) end
end

local function syncModel()
    if not modelLb then return end
    local sel = modelLb:Get()
    if sel == lastModelSel then return end
    lastModelSel = sel
    C.setLocalModel(modelPaths and modelPaths[sel] or nil)
end

do
    local page, match, origRel, ok = nil, nil, nil, false

    local function r_i32(a) return ffi.cast("int32_t*",  a)[0] end
    local function w_u8 (a, v) ffi.cast("uint8_t*", a)[0] = v end
    local function w_i32(a, v) ffi.cast("int32_t*", a)[0] = v end
    local function w_f32(a, v) ffi.cast("float*",   a)[0] = v end

    local function le64(v)
        local t = {}
        for _ = 1, 8 do t[#t + 1] = v % 256; v = math.floor(v / 256) end
        return t
    end

    local function alloc_near(target, size)
        local gran = 0x10000
        local base = target - (target % gran)
        for i = 1, 0x8000 do
            local lo, hi = base - i * gran, base + i * gran
            if lo > 0x10000 then
                local p = ffi.C.VirtualAlloc(ffi.cast("void*", lo), size, 0x3000, 0x40)
                if p ~= nil then return p end
            end
            local p2 = ffi.C.VirtualAlloc(ffi.cast("void*", hi), size, 0x3000, 0x40)
            if p2 ~= nil then return p2 end
        end
        return nil
    end

    local function install()
        if type(ffi) ~= "table" then print("[TROPA DO PINO PRETO] VM: no ffi"); return false end
        pcall(function() ffi.cdef [[
            void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
            int   VirtualProtect(void*, size_t, uint32_t, uint32_t*);
            void* GetCurrentProcess(void);
            int   FlushInstructionCache(void*, void*, size_t);
        ]] end)

        local a = mem.FindPattern("client.dll", SIG.vm)
        if not a or a == 0 then print("[TROPA DO PINO PRETO] VM: sig not found"); return false end
        match = a
        local orig = a + 5 + r_i32(a + 1)

        local p = alloc_near(orig, 0x1000)
        if p == nil then print("[TROPA DO PINO PRETO] VM: alloc failed"); return false end
        page = tonumber(ffi.cast("uintptr_t", p))
        local code = page + 16

        local b = { 0x53, 0x56, 0x48,0x83,0xEC,0x28, 0x48,0x89,0xD6, 0x48,0xB8 }
        for _, v in ipairs(le64(orig)) do b[#b + 1] = v end
        for _, v in ipairs({ 0xFF,0xD0, 0x48,0xBB }) do b[#b + 1] = v end
        for _, v in ipairs(le64(page)) do b[#b + 1] = v end
        for _, v in ipairs({
            0x8B,0x0B, 0x85,0xC9, 0x74,0x2B,
            0xF3,0x0F,0x10,0x4B,0x04, 0xF3,0x0F,0x58,0x0E, 0xF3,0x0F,0x11,0x0E,
            0xF3,0x0F,0x10,0x4B,0x08, 0xF3,0x0F,0x58,0x4E,0x04, 0xF3,0x0F,0x11,0x4E,0x04,
            0xF3,0x0F,0x10,0x4B,0x0C, 0xF3,0x0F,0x58,0x4E,0x08, 0xF3,0x0F,0x11,0x4E,0x08,
            0x48,0x83,0xC4,0x28, 0x5E, 0x5B, 0xC3,
        }) do b[#b + 1] = v end
        for i = 0, #b - 1 do w_u8(code + i, b[i + 1]) end
        w_i32(page, 0); w_f32(page + 4, 0); w_f32(page + 8, 0); w_f32(page + 12, 0)

        local rel = code - (match + 5)
        if rel < -2147483648 or rel > 2147483647 then print("[TROPA DO PINO PRETO] VM: rel32 overflow"); return false end
        origRel = r_i32(match + 1)
        local old = ffi.new("uint32_t[1]")
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
        w_i32(match + 1, rel)
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        pcall(function() ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), ffi.cast("void*", match), 5) end)
        print("[TROPA DO PINO PRETO] VM: installed")
        return true
    end

    pcall(function() ok = install() end)

    function VM.set(on, x, y, z)
        if not ok or not page then return end
        w_i32(page, on and 1 or 0)
        w_f32(page + 4, x or 0)
        w_f32(page + 8, y or 0)
        w_f32(page + 12, z or 0)
    end

    function VM.uninstall()
        if not (ok and match and origRel) then return end
        pcall(function()
            local old = ffi.new("uint32_t[1]")
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
            w_i32(match + 1, origRel)
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        end)
    end
end
pcall(function() callbacks.Register("Unload", function() pcall(VM.uninstall) end) end)

local lastVm = nil
local function syncVm()
    local on = cbVm:Get()
    local x, y, z = vmX:Get(), vmY:Get(), vmZ:Get()
    VM.set(on, x, y, z)
    local s = (on and "1" or "0") .. ":" .. x .. ":" .. y .. ":" .. z
    if s ~= lastVm then
        lastVm = s
        C.setOpt("vm_on", on)
        C.setOpt("vm_x", x); C.setOpt("vm_y", y); C.setOpt("vm_z", z)
    end
end

do
    local f = ffi
    local FFF, FNF, FCL, GCD, WINEXEC
    local soundDir = ".\\csgo\\sounds"
    if type(f) == "table" then
        pcall(function() f.cdef [[ void* GetModuleHandleA(const char*); void* GetProcAddress(void*, const char*); ]] end)
        pcall(function() f.cdef [[ typedef struct { uint32_t attr; uint8_t pad[40]; char nm[260]; char alt[14]; } AWSNDFD; ]] end)
        local function P(nm, t)
            local h = f.C.GetModuleHandleA("kernel32.dll"); if h == nil then return nil end
            local p = f.C.GetProcAddress(h, nm); return (p ~= nil) and f.cast(t, p) or nil
        end
        FFF = P("FindFirstFileA",       "void*(*)(const char*, void*)")
        FNF = P("FindNextFileA",        "int(*)(void*, void*)")
        FCL = P("FindClose",            "int(*)(void*)")
        GCD = P("GetCurrentDirectoryA", "uint32_t(*)(uint32_t, char*)")
        WINEXEC = P("WinExec",          "uint32_t(*)(const char*, uint32_t)")
        pcall(function()
            if GCD then
                local eb = f.new("char[?]", 1024)
                local cwd = f.string(eb, GCD(1024, eb))
                soundDir = cwd:gsub("[\\/]bin[\\/]win64.*$", "\\csgo\\sounds")
            end
        end)
    end
    HS.openSoundDir = function()
        if WINEXEC then pcall(function() WINEXEC('explorer.exe "' .. soundDir .. '"', 5) end) end
    end

    local function scanSounds()
        local names = {}
        pcall(function()
            if not (f and FFF and FNF and FCL) then return end
            local INVALID = f.cast("void*", f.cast("intptr_t", -1))
            local fd = f.new("AWSNDFD")
            local h = FFF(soundDir .. "\\*.vsnd_c", fd)
            if h ~= INVALID then
                repeat
                    local nm = f.string(fd.nm)
                    if nm:sub(-7):lower() == ".vsnd_c" then names[#names + 1] = nm:sub(1, #nm - 7) end
                until FNF(h, fd) == 0
                FCL(h)
            end
        end)
        table.sort(names)
        local paths = {}
        for i = 1, #names do paths[i] = names[i] end
        if #names == 0 then names[1] = "[ put .vsnd_c in csgo\\sounds ]" end
        return names, paths
    end
    HS.scan = scanSounds
    SND_NAMES, SND_PATHS = scanSounds()

    local function resolve(cmb)
        return tostring(SND_PATHS[cmb:Get()] or "")
    end

    local _sndQueue = {}

    local function play(path, vol)
        if path == "" then return end
        vol = (tonumber(vol) or 100) / 100
        if vol <= 0 then return end
        _sndQueue[#_sndQueue + 1] = { path = path, vol = vol }
    end

    function HS.flushSounds()
        if #_sndQueue == 0 then return end
        for _, s in ipairs(_sndQueue) do
            pcall(function() client.SetConVar("snd_toolvolume", s.vol, true) end)
            pcall(function() client.Command("play sounds\\" .. s.path, true) end)
        end
        _sndQueue = {}
    end

    function HS.playHit()  play(resolve(hsCmb), hsVol:Get()) end
    function HS.playKill() play(resolve(ksCmb), ksVol:Get()) end

    local bit_ = rawget(_G, "bit")
    local DLL  = "client.dll"
    local off  = {}
    off.dwEntityList            = C.offsets and C.offsets.dwEntityList
    off.dwLocalPlayerController = C.offsets and C.offsets.dwLocalPlayerController
    pcall(function()
        local j = http.Get("https://raw.githubusercontent.com/a2x/cs2-dumper/main/output/client_dll.json")
        off.m_iszPlayerName = j and tonumber(j:match('"m_iszPlayerName"%s*:%s*(%d+)')) or nil
        off.m_iPing         = j and tonumber(j:match('"m_iPing"%s*:%s*(%d+)')) or nil
    end) 

    local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift
    local function slot(elist, idx)
        if not valid(elist) then return nil end
        local chunk = r_ptr(elist + 8 * rshift(idx, 9) + 16); if not valid(chunk) then return nil end
        local e = r_ptr(chunk + 112 * band(idx, 0x1FF))
        if valid(e) and valid(r_ptr(e)) then return e end
        return nil
    end

    local function nameOf(elist, plyslot)
        if not (off.m_iszPlayerName and type(ffi) == "table") then return nil end
        local c = slot(elist, (plyslot or -1) + 1)
        if not valid(c) then return nil end
        local s
        pcall(function() s = ffi.string(ffi.cast("const char*", c + off.m_iszPlayerName)) end)
        if s and #s > 0 and #s < 64 then return s end
        return nil
    end

    local function localCtrlList()
        if not (type(ffi) == "table" and band and off.dwLocalPlayerController and off.dwEntityList) then return nil, nil end
        local base = mem.GetModuleBase(DLL); if not base then return nil, nil end
        local lctrl = r_ptr(base + off.dwLocalPlayerController)
        local elist = r_ptr(base + off.dwEntityList)
        if valid(lctrl) and valid(elist) then return lctrl, elist end
        return nil, nil
    end

    function HS.localInfo()
        local lctrl = localCtrlList()
        if not valid(lctrl) then return nil, nil end
        local nick, ping
        if off.m_iszPlayerName then
            pcall(function()
                local s = ffi.string(ffi.cast("const char*", lctrl + off.m_iszPlayerName))
                if s and #s > 0 and #s < 64 then nick = s end
            end)
        end
        if off.m_iPing then
            pcall(function()
                local p = ffi.cast("int32_t*", lctrl + off.m_iPing)[0]
                if p and p >= 0 and p < 10000 then ping = p end
            end)
        end
        return nick, ping
    end

    function HS.nameBySlot(s)
        local _, elist = localCtrlList()
        if not valid(elist) then return nil end
        return nameOf(elist, s)
    end

    local MISS_DELAY = 16
    local frameId = 0
    local pend = {}

    local HG = { [0] = "body", [1] = "head", [2] = "chest", [3] = "stomach",
                 [4] = "l.arm", [5] = "r.arm", [6] = "l.leg", [7] = "r.leg", [10] = "gear" }

    local function evHurt(d)
        local dmg = d.dmg_health or 0
        if dmg <= 0 then return end
        local lctrl, elist = localCtrlList()
        local iAttack, iHurt = true, false
        if lctrl then
            iAttack = slot(elist, (d.attacker or -1) + 1) == lctrl
            iHurt   = slot(elist, (d.userid   or -1) + 1) == lctrl
        end
        if d.userid == d.attacker then iAttack = false end

        local hg = HG[d.hitgroup or 0] or "body"
        if iAttack then
            for i = 1, #pend do if not pend[i].hit then pend[i].hit = true; break end end
            local dead = (d.health or 1) <= 0
            local who  = nameOf(elist, d.userid) or "player"
            if dead then
                if ksOn:Get() then HS.playKill() end
                if hlOn:Get() and hlKill:Get() then
                    M:Hitlog("kill", dmg, "killed " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            else
                if hsOn:Get() then HS.playHit() end
                if hlOn:Get() and hlHit:Get() then
                    M:Hitlog("hit", dmg, "hit " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            end
        elseif iHurt then
            local who = nameOf(elist, d.attacker) or "player"
            if hlOn:Get() and hlHurt:Get() then
                M:Hitlog("hurt", dmg, "hurt by " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
            end
        end
    end

    local function evFire(d)
        if not (hlOn:Get() and hlMiss:Get()) then return end
        local adef = C.activeDef()
        if adef and C.isKnife(adef) then return end
        local lctrl, elist = localCtrlList()
        if not lctrl then return end
        if slot(elist, (d.userid or -1) + 1) ~= lctrl then return end
        pend[#pend + 1] = { f = frameId, hit = false }
    end

    function HS.onEvent(ev)
        local name
        pcall(function() name = ev:GetName() end)
        if name == "player_hurt" then
            local d = {}
            pcall(function()
                d.attacker   = ev:GetInt("attacker")
                d.userid     = ev:GetInt("userid")
                d.health     = ev:GetInt("health")
                d.dmg_health = ev:GetInt("dmg_health")
                d.hitgroup   = ev:GetInt("hitgroup")
            end)
            evHurt(d)
        elseif name == "weapon_fire" then
            local d = {}
            pcall(function() d.userid = ev:GetInt("userid") end)
            evFire(d)
        end
    end

    function HS.missTick()
        frameId = frameId + 1
        if #pend == 0 then return end
        local keep = {}
        for i = 1, #pend do
            local s = pend[i]
            if frameId - s.f >= MISS_DELAY then
                if not s.hit and hlOn:Get() and hlMiss:Get() then M:Hitlog("miss", nil, "missed shot") end
            else
                keep[#keep + 1] = s
            end
        end
        pend = keep
    end

    local lastHs = nil
    function HS.sync()
        local s = table.concat({ hsOn:Get() and 1 or 0, hsCmb:Get(), hsVol:Get(),
                                 ksOn:Get() and 1 or 0, ksCmb:Get(), ksVol:Get() }, ":")
        if s == lastHs then return end
        lastHs = s
        C.setOpt("hs_on2", hsOn:Get()); C.setOpt("hs_snd2", hsCmb:Get()); C.setOpt("hs_vol2", hsVol:Get())
        C.setOpt("ks_on2", ksOn:Get()); C.setOpt("ks_snd2", ksCmb:Get()); C.setOpt("ks_vol2", ksVol:Get())
    end
end

local RG = { ok = false, ids = {}, names = {}, allow = {}, add = 200, enabled = false, installed = false }
do
    local f = ffi
    local CITY = {
        ams = "Amsterdam", atl = "Atlanta", bom = "Mumbai", maa = "Chennai",
        can = "Guangzhou", sha = "Shanghai", tyo = "Tokyo", hkg = "Hong Kong",
        seo = "Seoul", sgp = "Singapore", syd = "Sydney", dxb = "Dubai",
        fra = "Frankfurt", lhr = "London", lux = "Luxembourg", par = "Paris",
        mad = "Madrid", sto = "Stockholm", vie = "Vienna", waw = "Warsaw",
        hel = "Helsinki", iad = "Washington", ord = "Chicago", lax = "Los Angeles",
        sea = "Seattle", dfw = "Dallas", okc = "Oklahoma", gru = "Sao Paulo",
        sao = "Sao Paulo", scl = "Santiago", lim = "Lima", bog = "Bogota",
        eat = "Moscow", sto2 = "Stockholm", jhb = "Johannesburg", pwj = "Tianjin",
        pwg = "Guangzhou", pwz = "Chengdu", tsn = "Tianjin", cpt = "Cape Town",
    }

    local function decode(id)
        local code = ""
        for sh = 24, 0, -8 do
            local c = floor(id / 2 ^ sh) % 256
            if c >= 32 and c < 127 then code = code .. string.char(c) end
        end
        return (code:gsub("%s", ""))
    end

    function RG.label(id)
        local code = decode(id)
        local city = CITY[code:lower()]
        if city then return city .. " (" .. code .. ")" end
        return code ~= "" and code or ("#" .. id)
    end

    if type(f) == "table" then
        local IDX_COUNT, IDX_LIST = 10, 11
        local TARGETS = {
            { rva = 0x13F050, steal = 17 },             -- GetPingToDataCenter (vtable idx 8)
            { rva = 0x13EBB0, steal = 15, call = 10 },  -- GetDirectPingToPOP  (vtable idx 9)
        }

        local DLL  = "steamnetworkingsockets.dll"
        local ACCS = { "SteamNetworkingUtils_LibV4", "SteamNetworkingUtils_LibV3", "SteamNetworkingUtils_LibV2" }

        local hmod = f.C.GetModuleHandleA(DLL)
        local base = hmod ~= nil and tonumber(f.cast("uintptr_t", hmod)) or nil

        local utils, vtbl, getCount, getList
        if hmod ~= nil then
            local acc
            for _, nm in ipairs(ACCS) do
                local p = f.C.GetProcAddress(hmod, nm)
                if p ~= nil then acc = p; break end
            end
            if acc ~= nil then
                local ok2, u = pcall(function() return f.cast("void*(*)(void)", acc)() end)
                if ok2 and u ~= nil then utils = u end
            end
            if utils ~= nil then
                vtbl = f.cast("void***", utils)[0]
                if vtbl ~= nil then
                    getCount = f.cast("int(*)(void*)", vtbl[IDX_COUNT])
                    getList  = f.cast("int(*)(void*, uint32_t*, int)", vtbl[IDX_LIST])
                end
            end
        end

        local w_u8  = function(a, v) f.cast("uint8_t*",  a)[0] = v end
        local w_i32 = function(a, v) f.cast("int32_t*",  a)[0] = v end
        local le64  = function(a, v) f.cast("uint64_t*", a)[0] = f.cast("uint64_t", v) end

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

        local hooks, keeps = {}, {}

        local function hookFunc(rva, steal, callOff)
            local T  = base + rva
            local b0 = f.cast("uint8_t*", T)
            local p  = alloc_near(T); if p == nil then return nil end
            local TR = tonumber(f.cast("uintptr_t", p))

            local saved = {}
            for i = 0, steal - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end

            if callOff then
                local relOrig    = f.cast("int32_t*", T + callOff + 1)[0]
                local callTarget = (T + callOff + 5) + relOrig
                local newRel     = callTarget - (TR + callOff + 5)
                if newRel < -2147483648 or newRel > 2147483647 then return nil end
                w_i32(TR + callOff + 1, newRel)
            end

            w_u8(TR + steal, 0xFF); w_u8(TR + steal + 1, 0x25); w_i32(TR + steal + 2, 0)
            le64(TR + steal + 6, T + steal)

            local orig = f.cast("int(*)(void*, uint32_t, uint32_t*)", f.cast("void*", TR))
            local cb = f.cast("int(*)(void*, uint32_t, uint32_t*)", function(self, popid, via)
                local r = orig(self, popid, via)
                if RG.enabled and r >= 0 and next(RG.allow) ~= nil then
                    if RG.allow[tonumber(popid)] then
                        if RG.minimize then return 1 end
                    else
                        return r + RG.add
                    end
                end
                return r
            end)
            keeps[#keeps + 1] = cb

            local old = f.new("uint32_t[1]")
            if f.C.VirtualProtect(f.cast("void*", T), steal, 0x40, old) == 0 then return nil end
            w_u8(T, 0xFF); w_u8(T + 1, 0x25); w_i32(T + 2, 0); le64(T + 6, tonumber(f.cast("uintptr_t", cb)))
            for i = 14, steal - 1 do w_u8(T + i, 0x90) end
            f.C.VirtualProtect(f.cast("void*", T), steal, old[0], old)
            pcall(function() f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", T), steal) end)

            hooks[#hooks + 1] = { T = T, saved = saved, steal = steal }
            return orig
        end

        local function install()
            if not base then return false end
            local any = false
            for _, t in ipairs(TARGETS) do
                local o = nil
                pcall(function() o = hookFunc(t.rva, t.steal, t.call) end)
                if o then
                    any = true
                    if not RG.ping then RG.ping = o end
                end
            end
            RG.installed = any
            return any
        end

        function RG.uninstall()
            for _, h in ipairs(hooks) do
                pcall(function()
                    local old = f.new("uint32_t[1]")
                    f.C.VirtualProtect(f.cast("void*", h.T), h.steal, 0x40, old)
                    for i = 0, h.steal - 1 do w_u8(h.T + i, h.saved[i]) end
                    f.C.VirtualProtect(f.cast("void*", h.T), h.steal, old[0], old)
                    f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", h.T), h.steal)
                end)
            end
            RG.installed = false
        end

        local function pingOf(id)
            if not RG.ping then return nil end
            local r
            pcall(function()
                local via = f.new("uint32_t[1]")
                r = RG.ping(nil, id, via)
            end)
            if r and r >= 0 and r < 100000 then return r end
            return nil
        end

        local function enumerate()
            if utils == nil or not getCount or not getList then return end
            local n = getCount(utils)
            if n <= 0 then return end
            if n > 256 then n = 256 end
            local buf = f.new("uint32_t[?]", n)
            local got = getList(utils, buf, n)
            if got < 0 then return end
            if got > n then got = n end
            local all, hasPing = {}, {}
            for i = 0, got - 1 do
                local id    = tonumber(buf[i])
                local known = CITY[decode(id):lower()] ~= nil
                local ping  = pingOf(id)
                local nm    = RG.label(id) .. (ping and ("  " .. ping .. "ms") or "")
                local e = { id = id, name = nm, known = known, ping = ping }
                all[#all + 1] = e
                if ping ~= nil and ping <= 250 then hasPing[#hasPing + 1] = e end
            end
            local use = (#hasPing > 0) and hasPing or all
            table.sort(use, function(a, b)
                if (a.ping ~= nil) ~= (b.ping ~= nil) then return a.ping ~= nil end
                if a.ping and b.ping and a.ping ~= b.ping then return a.ping < b.ping end
                if a.known ~= b.known then return a.known end
                return a.name < b.name
            end)
            local ids, names = {}, {}
            for _, e in ipairs(use) do ids[#ids + 1] = e.id; names[#names + 1] = e.name end
            if #ids > 0 then RG.ids = ids; RG.names = names end
        end
        RG.enumerate = enumerate

        local okI = false
        pcall(function() okI = install() end)
        if utils ~= nil and vtbl ~= nil then pcall(enumerate) end
        RG.ok = okI
        if okI then print("[TROPA DO PINO PRETO] region: hooked " .. #hooks .. " fns (" .. #RG.ids .. " pops)")
        else            print("[TROPA DO PINO PRETO] region: hook failed") end
    end

    if #RG.names == 0 then RG.names = { "[ join a server, then Refresh ]" } end
end
pcall(function() callbacks.Register("Unload", function() pcall(RG.uninstall) end) end)

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
        if type(f) ~= "table" then print("[TROPA DO PINO PRETO] namechanger: no ffi"); return false end
        local a = mem.FindPattern(DLL, SIG_SETINFO)
        if not a or a == 0 then print("[TROPA DO PINO PRETO] namechanger: sig not found"); return false end
        T = a
        local b0 = f.cast("uint8_t*", T)
        local p = alloc_near(T); if p == nil then print("[TROPA DO PINO PRETO] namechanger: alloc failed"); return false end
        local TR = tonumber(f.cast("uintptr_t", p))

        local saved = {}
        for i = 0, STEAL - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end
        w_u8(TR + STEAL, 0xFF); w_u8(TR + STEAL + 1, 0x25); w_i32(TR + STEAL + 2, 0)
        le64(TR + STEAL + 6, T + STEAL)

        orig = f.cast("char (*)(void*, void*)", f.cast("void*", TR))
        keepCb = f.cast("char (*)(void*, void*)", onSetInfo)

        local old = f.new("uint32_t[1]")
        if f.C.VirtualProtect(f.cast("void*", T), STEAL, 0x40, old) == 0 then
            print("[TROPA DO PINO PRETO] namechanger: protect failed"); return false
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
        NC._diag = { base = base, cvar = cvar, vt = vt, find = findAddr }
        pcall(function()
            local ref = tonumber(findfn(f.cast("void*", cvar), outbuf, nameC, 1))
            NC._diag.ref = ref
            if not ref or ref < 0x10000 then return end
            local handle = f.cast("uint32_t*", ref)[0]
            NC._diag.handle = tonumber(handle)
            resolve(res, handle, -1)
            local obj = tonumber(res[1])
            NC._diag.obj = obj
            if not valid(obj) then return end
            NC._flags = obj + FLAGS_OFF
            local p = f.cast("uint32_t*", NC._flags)
            NC._diag.old = tonumber(p[0])
            p[0] = bit_.band(bit_.bor(p[0], F_USERINFO), bit_.bnot(F_PROTECTED))
            NC._diag.new = tonumber(p[0])
            done = true
        end)
        return done
    end

    function NC.dump()
        local d = NC._diag or {}
        local function hx(v) return v and string.format("%X", v) or "nil" end
        print("[TROPA DO PINO PRETO] NC: base=" .. hx(d.base) .. " cvar=" .. hx(d.cvar) ..
              " vt=" .. hx(d.vt) .. " find=" .. hx(d.find) .. " ref=" .. hx(d.ref) ..
              " handle=" .. tostring(d.handle) .. " obj=" .. hx(d.obj) ..
              " flags " .. hx(d.old) .. "->" .. hx(d.new))
    end

    function NC.steamName()
        if type(f) ~= "table" then return nil end
        if NC._steam then return NC._steam end
        local h = f.C.GetModuleHandleA("steam_api64.dll"); if h == nil then return nil end
        local getName = f.C.GetProcAddress(h, "SteamAPI_ISteamFriends_GetPersonaName")
        if getName == nil then return nil end
        local accFn
        for _, v in ipairs({ "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018",
                             "SteamAPI_SteamFriends_v019", "SteamAPI_SteamFriends_v016",
                             "SteamAPI_SteamFriends_v020" }) do
            local p = f.C.GetProcAddress(h, v)
            if p ~= nil then accFn = p; break end
        end
        if accFn == nil then return nil end
        local res
        pcall(function()
            local iface = f.cast("void* (*)(void)", accFn)()
            if iface == nil then return end
            local s = f.cast("const char* (*)(void*)", getName)(iface)
            if s ~= nil then
                local str = f.string(s)
                if #str > 0 and #str < 64 then res = str end
            end
        end)
        if res then NC._steam = res end
        return res
    end

    function NC.origName()
        return NC.steamName() or NC._captured
    end

    local okI = false
    pcall(function() okI = install() end)
    NC.ok = okI
    if okI then print("[TROPA DO PINO PRETO] namechanger: hooked SetInfo @ " .. string.format("%X", T))
    else        print("[TROPA DO PINO PRETO] namechanger: install failed") end
end
pcall(function() callbacks.Register("Unload", function() pcall(NC.uninstall) end) end)

local CHAT = { ok = false }
do
    local f = ffi
    local SIG_CHAT = "4C 89 4C 24 20 53 56 B8 38 10 00 00 E8 ?? ?? ?? ?? 48 2B E0 48 8B 0D ?? ?? ?? ?? 41 8B D8 48 8B F2"
    local fn, flags
    if type(f) == "table" then
        local a = mem.FindPattern("client.dll", SIG_CHAT)
        if a and a ~= 0 then
            fn    = f.cast("void(*)(void*, void*, uint32_t, const char*, const char*)", f.cast("void*", a))
            flags = f.new("int[1]", 0x0100)
            CHAT.ok = true
            print("[TROPA DO PINO PRETO] chat: hooked print @ " .. string.format("%X", a))
        else
            print("[TROPA DO PINO PRETO] chat: print sig not found")
        end
    end
    function CHAT.print(text)
        if not (CHAT.ok and fn) then return false end
        return pcall(function() fn(nil, flags, 0, "%s", tostring(text)) end)
    end
end

local VR = { q = {} }
do
    local G, R, W, P = string.char(4), string.char(2), string.char(1), string.char(14)
    local function pfx() return "[" .. P .. "pinopreto" .. W .. "] " end

    local function startMsg(initiator, target)
        return pfx() .. initiator .. " started a vote to kick " .. target,
               initiator .. " wants to kick " .. target
    end
    local function castMsg(name, yes)
        local yn = yes and (G .. "yes" .. W) or (R .. "no" .. W)
        return pfx() .. name .. " voted " .. yn,
               name .. " voted " .. (yes and "yes" or "no")
    end

    local function push(chat, note, kind) VR.q[#VR.q + 1] = { chat = chat, note = note, kind = kind } end

    local function pname(slot)
        if not slot or slot < 0 then return "player" end
        local n = HS.nameBySlot(slot)
        if type(n) == "string" and #n > 0 and #n < 64 then return n end
        return "player"
    end

    function VR.flush()
        local total = #VR.q; if total == 0 then return end
        local q = VR.q; VR.q = {}
        local mode = (VR._mode and VR._mode()) or 3
        for i = 1, total do
            local it = q[i]
            if mode == 1 or mode == 3 then pcall(function() CHAT.print(it.chat) end) end
            if mode == 2 or mode == 3 then pcall(function() M:Notify(it.note, it.kind) end) end
        end
    end

    function VR.test()
        local a, b = startMsg("initiator", "target"); push(a, b, "info")
        local c, d = castMsg("player", true);  push(c, d, "success")
        local e, g = castMsg("player", false); push(e, g, "error")
    end

    function VR.onEvent(ev)
        if not (VR._on and VR._on()) then return end
        local name
        pcall(function() name = ev:GetName() end)
        if name == "vote_cast" then
            local opt
            pcall(function() opt = ev:GetInt("vote_option") end)
            if opt == nil or opt < 0 then return end
            local voter
            pcall(function() voter = ev:GetInt("userid") end)
            local yes = (opt == 0)
            local c, n = castMsg(pname(voter), yes)
            push(c, n, yes and "success" or "error")
        elseif name == "vote_started" or name == "vote_begin" then
            local initiator
            pcall(function() initiator = ev:GetInt("entityid") end)
            if not initiator or initiator <= 0 then pcall(function() initiator = ev:GetInt("userid") end) end
            local tid
            pcall(function()
                local disp = ev:GetString("disp_str")
                if type(disp) == "string" then
                    local m = disp:match(":(%d+):")
                    if m then tid = tonumber(m) end
                end
            end)
            local c, n = startMsg(pname(initiator), tid and pname(tid) or "player")
            push(c, n, "info")
        end
    end
end
pcall(function()
    for _, e in ipairs({ "player_hurt", "weapon_fire", "vote_started", "vote_begin", "vote_cast" }) do
        pcall(function() client.AllowListener(e) end)
    end
    callbacks.Register("FireGameEvent", "TROPA DO PINO PRETO_Events", function(ev)
        pcall(HS.onEvent, ev)
        pcall(VR.onEvent, ev)
        -- Bomb timer
        pcall(function()
            local name = ev:GetName()
            if name == "bomb_planted" then
                BOMB.planted = true
                BOMB.time = globals.RealTime and globals.RealTime() or os.clock()
                pcall(function()
                    local site = ev:GetInt("site")
                    BOMB.site = site == 0 and "A" or "B"
                end)
            elseif name == "bomb_defused" or name == "bomb_exploded" or name == "round_start" then
                BOMB.planted = false
            elseif name == "round_end" then
                _spamRoundCount = (_spamRoundCount or 0) + 1
                if spamVac and spamVac:Get() and not _spamVacSent then
                    local target = math.floor((spamVacRound and spamVacRound:Get() or 12) + 0.5)
                    if _spamRoundCount >= target then
                        local vacMsg = "gg" .. string.rep("\xE1\x85\xA0", 40) .. "VACNET has detected a cheater and ended the match. This match will not affect you."
                        pcall(function() client.ChatSay(vacMsg) end)
                        _spamVacSent = true
                    end
                end
            end
        end)
    end)
end)

local tab = M:Tab("Skins")

-- Category system
CATEGORIES = {
    { name = "Knives",       filter = "knife" },
    { name = "Gloves",       filter = "glove" },
    { name = "Rifles",       defs = { 7, 16, 60, 8, 10, 13, 39 } },
    { name = "Snipers",      defs = { 9, 40, 38, 11 } },
    { name = "Pistols",      defs = { 1, 64, 2, 3, 4, 30, 32, 36, 61, 63 } },
    { name = "SMGs",         defs = { 17, 19, 26, 23, 33, 34, 24 } },
    { name = "Shotguns",     defs = { 25, 27, 35, 29 } },
    { name = "Machine Guns", defs = { 14, 28 } },
}

local catNames = {}
for i, cat in ipairs(CATEGORIES) do catNames[i] = cat.name end

local curCatItems = {}
curCatNames = {}
catFilteredMap = {}

filterByCategory = function(catIdx)
    local cat = CATEGORIES[catIdx]
    if not cat then return end
    curCatItems = {}
    curCatNames = {}
    catFilteredMap = {}
    for i, it in ipairs(C.items) do
        local match = false
        if cat.filter then
            match = (it.kind == cat.filter)
        elseif cat.defs then
            for _, d in ipairs(cat.defs) do
                if it.def == d then match = true; break end
            end
        end
        if match then
            curCatItems[#curCatItems + 1] = it
            curCatNames[#curCatNames + 1] = it.name
            catFilteredMap[#curCatNames] = i
        end
    end
    if #curCatNames == 0 then curCatNames = { "[ empty ]" } end
end
filterByCategory(1)

tab:Row()
local catSec = tab:Section("Category")
catCombo = catSec:Combo("", catNames, 1)
local wpnSec = tab:Section("Weapons")
weaponLb = wpnSec:Listbox("", curCatNames, "fill", 1)
weaponWd = wpnSec.ws[#wpnSec.ws]

tab:Col()
local sSec = tab:Section("Skins")
skinLb = sSec:Listbox("", { "[ select a weapon ]" }, "fill", 1)
skinWd = sSec.ws[#sSec.ws]

tab:Col()
local setSec = tab:Section("Settings")
sWear  = setSec:Slider("Wear / Float", 0.0001, 0.0, 1.0, 0.001, "%.3f")
sSeed  = setSec:Slider("Seed", 0, 0, 1000, 1)
cbAuto = setSec:Checkbox("Auto select weapon", false)

local actSec = tab:Section("Actions")
actSec:Button("Remove",    function() C.remove(item()) end)
actSec:Button("Reset All", function() C.resetAll() end)

local cfgSec = tab:Section("Config / Presets")
local presetCombo = cfgSec:Combo("Slot", { "Preset 1", "Preset 2", "Preset 3", "Preset 4", "Preset 5" }, 1)
cfgSec:Button("Save preset", function()
    local slot = presetCombo:Get()
    local cfg = {}
    for _, it in ipairs(C.items) do
        local c = C.getCfg(it.def)
        if c then cfg[tostring(it.def)] = c end
    end
    cfg["_knifeDef"] = C.knifeDef()
    local serialized = {}
    for k, v in pairs(cfg) do
        if type(v) == "table" then
            serialized[#serialized + 1] = k .. "=" .. (v.paint or 0) .. "," .. (v.wear or 0.0001) .. "," .. (v.seed or 0) .. "," .. (v.kind or "weapon")
        else
            serialized[#serialized + 1] = k .. "=" .. tostring(v)
        end
    end
    C.setOpt("preset_" .. slot, table.concat(serialized, ";"))
    M:Info("Preset " .. slot .. " saved")
end)
cfgSec:Button("Load preset", function()
    local slot = presetCombo:Get()
    local data = C.getOpt("preset_" .. slot)
    if not data or data == "" then M:Error("Preset " .. slot .. " is empty"); return end
    C.resetAll()
    for entry in data:gmatch("[^;]+") do
        local key, vals = entry:match("^(.-)=(.+)$")
        if key and vals then
            if key:match("^%d+$") then
                local def = tonumber(key)
                local paint, wear, seed, kind = vals:match("^(%d+),([%d%.]+),(%d+),(%a+)$")
                if def and paint then
                    paint = tonumber(paint) or 0
                    wear = tonumber(wear) or 0.0001
                    seed = tonumber(seed) or 0
                    local it = nil
                    for _, item in ipairs(C.items) do
                        if item.def == def then it = item; break end
                    end
                    if it then C.apply(it, paint, wear, seed) end
                end
            end
        end
    end
    lastSel = -1
    lastSig = nil
    M:Info("Preset " .. slot .. " loaded")
end)
cfgSec:Button("Delete preset", function()
    local slot = presetCombo:Get()
    C.setOpt("preset_" .. slot, nil)
    M:Info("Preset " .. slot .. " deleted")
end)
cfgSec:Button("Reset all skins", function() C.clearConfig() end)

-- Override item() to use category-filtered items
_lastCat = 1
item = function()
    local sel = weaponLb:Get()
    local globalIdx = catFilteredMap[sel]
    if globalIdx then return C.items[globalIdx] end
    return nil
end

-- Category sync
local function syncCategory()
    local cat = catCombo:Get()
    if cat ~= _lastCat then
        _lastCat = cat
        filterByCategory(cat)
        weaponWd.items = curCatNames
        weaponWd.value = 1
        weaponWd.scroll = 0
        lastSel = -1
    end
end

local vtab = M:Tab("Visuals")

local submodels = vtab:Sub("Models")
submodels:Row()
local vSec = submodels:Section("List")
local mNames
mNames, modelPaths = C.modelList()
modelLb = vSec:Listbox("", mNames, "fill", 1)
modelWd = vSec.ws[#vSec.ws]
submodels:Col()
local vSsec = submodels:Section("Settings")
vSsec:Button("Refresh models", function()
    local cur = C.getLocalModel()
    local n, p = C.refreshModels()
    modelPaths     = p
    modelWd.items  = n
    modelWd.value  = 1
    modelWd.scroll = 0
    if cur then
        for i = 2, #p do if p[i] == cur then modelWd.value = i; break end end
    end
    lastModelSel = modelWd.value
end)

local sublocal = vtab:Sub("Local")
sublocal:Row()
local localSection = sublocal:Section("Local player")
cbVm = localSection:Checkbox("Viewmodel override", false)
vmX  = localSection:Slider("Offset X", 0, -30, 30, 0.1, "%.1f")
vmY  = localSection:Slider("Offset Y", 0, -30, 30, 0.1, "%.1f")
vmZ  = localSection:Slider("Offset Z", 0, -30, 30, 0.1, "%.1f")

local subsound = vtab:Sub("Sounds")
subsound:Row()
local hsSec = subsound:Section("Hit sound")
hsOn    = hsSec:Checkbox("Enabled", true)
hsCmb   = hsSec:Combo("Sound", SND_NAMES, 1)
hsCmbWd = hsSec.ws[#hsSec.ws]
hsVol   = hsSec:Slider("Volume", 100, 0, 100, 1, "%.0f")

subsound:Col()
local ksSec = subsound:Section("Kill sound")
ksOn    = ksSec:Checkbox("Enabled", false)
ksCmb   = ksSec:Combo("Sound", SND_NAMES, 1)
ksCmbWd = ksSec.ws[#ksSec.ws]
ksVol   = ksSec:Slider("Volume", 100, 0, 100, 1, "%.0f")

subsound:Col()
local tSec = subsound:Section("Preview")
tSec:Button("Play hit",  function() HS.playHit() end)
tSec:Button("Play kill", function() HS.playKill() end)
tSec:Button("Rescan", function()
    local n, p = HS.scan()
    SND_PATHS = p
    hsCmbWd.options = n; hsCmbWd.value = 1
    ksCmbWd.options = n; ksCmbWd.value = 1
end)
tSec:Button("Open folder", function() HS.openSoundDir() end)

local subhl = vtab:Sub("Hitlogs")
subhl:Row()
local hlSet = subhl:Section("Hitlog")
hlOn = hlSet:Checkbox("Enabled", true)
hlSet:Button("Reset position", function() M:HitlogResetPos() end)

subhl:Col()
local hlTypes = subhl:Section("Types")
hlHit  = hlTypes:Checkbox("Hit",  true)
hlKill = hlTypes:Checkbox("Kill", true)
hlHurt = hlTypes:Checkbox("Hurt", true)
hlMiss = hlTypes:Checkbox("Miss", false)
hlTypes:Button("Test", function()
    local d = math.random(8, 60)
    M:Hitlog("hit",  d, "hit player in head for " .. d .. "hp")
    M:Hitlog("kill", d, "killed player in head for " .. d .. "hp")
    M:Hitlog("miss", nil, "missed shot")
end)

subhl:Col()
local hlCol = subhl:Section("Colors")
local cMiss = hlCol:ColorPicker("Miss", { 235, 90, 90 })
local cHit  = hlCol:ColorPicker("Hit",  { 139, 124, 246 })
local cHurt = hlCol:ColorPicker("Hurt", { 245, 170, 70 })
local cKill = hlCol:ColorPicker("Kill", { 80, 200, 120 })

local WM_PARTS = { "cheat", "lua", "user", "nick", "fps", "ping" }
local WM_POS   = { "top-left", "top-right", "bottom-left", "bottom-right" }

local subwm = vtab:Sub("Watermark")
subwm:Row()
local wmSec = subwm:Section("Watermark")
wmOn    = wmSec:Checkbox("Enabled", true)
wmElems = wmSec:MultiCombo("Elements",
    { "Cheat name", "Lua name", "Username", "Nickname", "fps", "ping" }, { 2, 4, 5, 6 })
wmPos   = wmSec:Combo("Position", { "Top left", "Top right", "Bottom left", "Bottom right" }, 2)

local ncClock = (function()
    for _, fn in ipairs({ function() return globals.RealTime() end,
                          function() return globals.CurTime() end,
                          function() return os.clock() end }) do
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then return fn end
    end
    return function() return 0 end
end)()

local NC_LEET = {
    a = { "@", "4" }, b = { "6", "8" }, c = { "<" },
    e = { "3" },      f = { "ph" },     g = { "9", "6" }, h = { "#" },
    i = { "1", "!" },     l = { "1" },
    m = { "|\\/|" },  n = { "|\\|" },   o = { "0" },
    r = { "|2" },     s = { "$" }, t = { "7" },
    v = { "\\/" },    z = { "2" },
}

local function ncGlitch(target)
    local function corrupt()
        local chars = {}
        for i = 1, #target do
            local c = target:sub(i, i)
            local alt = NC_LEET[c:lower()]
            if i > 1 and i < #target and alt and math.random() < 0.4 then
                c = alt[math.random(#alt)]
            end
            chars[i] = c
        end
        return table.concat(chars)
    end
    local seq = {}
    local function burst(n)
        for _ = 1, n do seq[#seq + 1] = { t = corrupt(), ms = 55 } end
    end
    burst(6)
    seq[#seq + 1] = { t = target, ms = 2000 }
    burst(6)
    seq[#seq + 1] = { t = target, ms = 2000 }
    return seq
end

local NC_FEM = {
    { t = "",          ms = 550 },
    { t = "$F",         ms = 55 },  { t = "$f",         ms = 85 },
    { t = "$f3",        ms = 55 },  { t = "$fe",        ms = 85 },
    { t = "$fe|\\/|",   ms = 55 },  { t = "$pi",       ms = 85 },
    { t = "$pi6",      ms = 55 },  { t = "$pin",      ms = 85 },
    { t = "$pin0",     ms = 55 },  { t = "$pino",     ms = 85 },
    { t = "$pinop",    ms = 55 },  { t = "$pinop",    ms = 85 },
    { t = "$pinopre",   ms = 55 },  { t = "$pinopre",   ms = 85 },
    { t = "$pinopre@",  ms = 55 },  { t = "$pinopret",  ms = 85 },
    { t = "$pinopreto", ms = 55 },  { t = "$pinopreto", ms = 90 },
    { t = "$pinopreto",  ms = 70 }, { t = "$pinopreto$", ms = 2000 },
    { t = "$pinopreto",  ms = 70 }, { t = "$pinopreto",   ms = 70 },
    { t = "$pinopret",  ms = 60 },  { t = "$pinopre",   ms = 60 },
    { t = "$pinop",    ms = 60 },  { t = "$pino",     ms = 60 },
    { t = "$pin",      ms = 60 },  { t = "$pi",       ms = 60 },
    { t = "$fe",        ms = 60 },  { t = "$f",         ms = 60 },
}

local NC_AIM = {
    { t = "",            ms = 450 },
    { t = "[A]",           ms = 120 },  { t = "[AI]",          ms = 120 },
    { t = "[AIM]",         ms = 120 },  { t = "[AIMW]",        ms = 120 },
    { t = "[AIMWA]",       ms = 120 },  { t = "[AIMWAR]",      ms = 120 },
    { t = "[AIMWARE]",     ms = 110 }, { t = "[AIMWARE.]",    ms = 120 },
    { t = "[AIMWARE.N]",   ms = 90 },  { t = "[AIMWARE.NE]",  ms = 120 },
    { t = "[AIMWARE.NET]", ms = 2000 },
    { t = "[AIMWARE.NE]",  ms = 120 },  { t = "[AIMWARE.N]",   ms = 120 },
    { t = "[AIMWARE.]",    ms = 120 },  { t = "[AIMWARE]",     ms = 120 },
    { t = "[AIMWAR]",      ms = 120 },  { t = "[AIMWA]",       ms = 120 },
    { t = "[AIMW]",        ms = 120 },  { t = "[AIM]",         ms = 120 },
    { t = "[AI]",          ms = 120 },  { t = "[A]",           ms = 120 },
}

local NC_FEM_G = ncGlitch("$pinopreto$")
local NC_AIM_G = ncGlitch("[AIMWARE.NET]")

local function ncParse(str, defMs)
    local frames = {}
    for tok in (str .. ","):gmatch("([^,]*),") do
        if tok ~= "" then
            local t, ms = tok:match("^(.-):(%d+)$")
            if t then frames[#frames + 1] = { t = t, ms = tonumber(ms) }
            else      frames[#frames + 1] = { t = tok, ms = defMs } end
        end
    end
    return frames
end

local function ncFrameAt(seq, t, factor)
    factor = factor or 1
    local n = #seq; if n == 0 then return "" end
    local total = 0
    for i = 1, n do total = total + seq[i].ms * factor end
    if total <= 0 then return seq[1].t end
    local ms  = (t * 1000) % total
    local acc = 0
    for i = 1, n do
        acc = acc + seq[i].ms * factor
        if ms < acc then return seq[i].t end
    end
    return seq[n].t
end

local function ncValue(t)
    local src = ncSrc and ncSrc:Get() or 1
    local glitch = ncStyle and ncStyle:Get() == 2
    local s
    if src == 2 then
        s = ncFrameAt(glitch and NC_FEM_G or NC_FEM, t, (ncSpeed:Get() or 400) / 400)
    elseif src == 3 then
        s = ncFrameAt(glitch and NC_AIM_G or NC_AIM, t, (ncSpeed:Get() or 400) / 400)
    elseif src == 4 then
        s = ncFrameAt(ncParse(ncText:Get(), floor(ncSpeed:Get() or 400)), t, 1)
    else
        s = ncText:Get()
    end
    s = s or ""
    if ncMode and ncMode:Get() == 2 then
        local rn = NC.origName()
        if rn and rn ~= "" then s = (s == "") and rn or (s .. " " .. rn) end
    end
    return s
end

local function ncApply(val, raw)
    if not val or val == "" then return end
    pcall(NC.fixFlags)
    NC.setName(val)
    if raw then
        pcall(function() client.Command("setinfo name x", true) end)
    else
        pcall(function() client.Command('setinfo name "' .. val:gsub('"', '') .. '"', true) end)
    end
end

local ntab = M:Tab("Misc")

local subRegion = ntab:Sub("Region")
local rgSec = subRegion:Section("Matchmaking region")
rgOn    = rgSec:Checkbox("Enabled", false)
rgCmb   = rgSec:MultiCombo("Allowed regions", RG.names, {})
rgCmbWd = rgSec.ws[#rgSec.ws]
rgPen   = rgSec:Slider("Ping penalty", 200, 50, 250, 1, "%.0f")
rgMin   = rgSec:Checkbox("Minimize selected ping", true)
rgSec:Button("Refresh regions", function()
    if not RG.enumerate then return end
    local selIds = {}
    local sel = rgCmb:Get()
    for i, id in ipairs(RG.ids) do if sel[i] then selIds[id] = true end end
    RG.enumerate()
    local nv = {}
    for i, id in ipairs(RG.ids) do if selIds[id] then nv[i] = true end end
    rgCmbWd.options = RG.names
    rgCmbWd.value   = nv
end)

local subNC = ntab:Sub("Name Changer")
local ncSec = subNC:Section("Name changer")
ncOn     = ncSec:Checkbox("Enabled", false)
ncMode   = ncSec:Combo("Mode", { "Full name", "Clantag" }, 1)
ncSrc    = ncSec:Combo("Source", { "Static", "pinopreto", "Aimware", "Custom" }, 1)
ncStyle  = ncSec:Combo("Style", { "Typing", "Glitch" }, 1)
ncText   = ncSec:Input("Text / frames", "", "name  /  a:80,ai:80,aim:200")
ncSpeed  = ncSec:Slider("Frame ms", 400, 100, 1000, 10, "%.0f")
ncSec:Button("Apply once", function() ncApply(ncValue(ncClock()), false) end)

local subVR = ntab:Sub("Vote")
local vrSec = subVR:Section("Vote revealer")
vrOn   = vrSec:Checkbox("Enabled", false)
vrMode = vrSec:Combo("Mode", { "Chat", "Notification", "Both" }, 3)
vrSec:Button("Test", function() VR.test() end)

VR._on   = function() return vrOn:Get() end
VR._mode = function() return vrMode:Get() end


local lastWm
local function wmSync()
    local sel = wmElems:Get()
    local parts = {}
    for i, k in ipairs(WM_PARTS) do parts[k] = sel[i] and true or false end
    local nick, ping = HS.localInfo()
    M:WatermarkSet({
        enabled = wmOn:Get(),
        parts   = parts,
        user    = cheat.GetUserName(),
        nick    = nick,
        ping    = ping,
        pos     = WM_POS[wmPos:Get()],
    })

    local key = table.concat({ wmOn:Get() and 1 or 0, parts.cheat and 1 or 0, parts.lua and 1 or 0,
                               parts.user and 1 or 0, parts.nick and 1 or 0, parts.fps and 1 or 0,
                               parts.ping and 1 or 0, wmPos:Get() }, ":")
    if key ~= lastWm then
        lastWm = key
        C.setOpt("wm_on", wmOn:Get())
        for _, k in ipairs(WM_PARTS) do C.setOpt("wm_" .. k, parts[k]) end
        C.setOpt("wm_pos", wmPos:Get())
    end
end

local lastRg
local function rgSync()
    if not RG.ok then return end
    RG.enabled  = rgOn:Get()
    RG.add      = floor(rgPen:Get() + 0.5)
    RG.minimize = rgMin:Get()
    local sel  = rgCmb:Get()
    local allow, picks = {}, {}
    for i, id in ipairs(RG.ids) do
        if sel[i] then allow[id] = true; picks[#picks + 1] = id end
    end
    RG.allow = allow
    local key = (RG.enabled and "1" or "0") .. ":" .. RG.add .. ":" .. (RG.minimize and "1" or "0") .. ":" .. table.concat(picks, ",")
    if key ~= lastRg then
        lastRg = key
        C.setOpt("rg_on", RG.enabled)
        C.setOpt("rg_pen", RG.add)
        C.setOpt("rg_min", RG.minimize)
        C.setOpt("rg_sel", table.concat(picks, ","))
    end
end

local lastNcOn, lastNcCfg, ncTrig, lastSent, lastInGame = nil, nil, 0, nil, false
local function ncSync()
    if not NC.ok then return end
    local on = ncOn:Get()
    NC.enabled = on

    local cfg = table.concat({ on and 1 or 0, ncMode:Get(), ncSrc:Get(), ncText:Get(),
                               floor(ncSpeed:Get() + 0.5) }, "|")
    if cfg ~= lastNcCfg then
        lastNcCfg = cfg
        C.setOpt("nc_on", on);          C.setOpt("nc_mode", ncMode:Get())
        C.setOpt("nc_src", ncSrc:Get()); C.setOpt("nc_text", ncText:Get())
        C.setOpt("nc_speed", floor(ncSpeed:Get() + 0.5))
    end

    if on ~= lastNcOn then
        lastNcOn = on
        ncTrig, lastSent = 0, nil
        if on then
            local nick = select(1, HS.localInfo())
            if nick and nick ~= "" then NC._captured = nick end
            NC.steamName()
            NC._restore = nil
        else
            NC.setName(nil)
            local rn = NC.origName()
            NC._restore  = (rn and rn ~= "") and rn or nil
            NC._restoreN = 0
        end
    end

    local inGame = HS.localInfo() and true or false
    if inGame and not lastInGame then NC._flags = nil; ncTrig, lastSent = 0, nil end
    lastInGame = inGame

    if NC._restore then
        if not inGame then return end
        local t = ncClock()
        if (t - ncTrig) >= 0.25 then
            ncTrig = t
            pcall(NC.fixFlags)
            local rn = NC._restore
            pcall(function() client.Command('setinfo name "' .. rn:gsub('"', '') .. '"', true) end)
            NC._restoreN = (NC._restoreN or 0) + 1
            if NC._restoreN >= 3 then NC._restore = nil end
        end
        return
    end

    if not on or not inGame then return end
    local t   = ncClock()
    local val = ncValue(t)
    if val == "" then return end
    if val ~= lastSent and (t - ncTrig) >= 0.2 then
        ncTrig, lastSent = t, val
        ncApply(val, true)
    end
end

local lastHlX, lastHlY, lastHlT
local function hlSync()
    M:HitlogSet({
        enabled = hlOn:Get(),
        colors  = { miss = cMiss:Get(), hit = cHit:Get(), hurt = cHurt:Get(), kill = cKill:Get() },
    })

    local x, y = M:HitlogPos()
    if x ~= lastHlX or y ~= lastHlY then
        lastHlX, lastHlY = x, y
        C.setOpt("hl_x", x); C.setOpt("hl_y", y)
    end

    local t = table.concat({ hlOn:Get() and 1 or 0, hlHit:Get() and 1 or 0, hlKill:Get() and 1 or 0,
                             hlHurt:Get() and 1 or 0, hlMiss:Get() and 1 or 0 }, ":")
    if t ~= lastHlT then
        lastHlT = t
        C.setOpt("hl_on", hlOn:Get());   C.setOpt("hl_hit", hlHit:Get())
        C.setOpt("hl_kill", hlKill:Get()); C.setOpt("hl_hurt", hlHurt:Get())
        C.setOpt("hl_miss", hlMiss:Get())
    end
end

local lastVr
local function vrSync()
    pcall(VR.flush)
    if not vrOn then return end
    local key = (vrOn:Get() and "1" or "0") .. ":" .. vrMode:Get()
    if key ~= lastVr then
        lastVr = key
        C.setOpt("vr_on", vrOn:Get()); C.setOpt("vr_mode", vrMode:Get())
    end
end

if C.loadConfig() then lastSel = -2 end
cbAuto:Set(C.getOpt("autoFollow") and true or false)
lastAuto = cbAuto:Get()

do
    local s = {}
    local hx = tonumber(C.getOpt("hl_x")); if hx then s.x_off = hx end
    local hy = tonumber(C.getOpt("hl_y")); if hy then s.y_off = hy end
    if next(s) then M:HitlogSet(s) end
end

cbVm:Set(C.getOpt("vm_on") and true or false)
vmX:Set(tonumber(C.getOpt("vm_x")) or 0)
vmY:Set(tonumber(C.getOpt("vm_y")) or 0)
vmZ:Set(tonumber(C.getOpt("vm_z")) or 0)

do
    local cur = C.getLocalModel()
    if cur and modelPaths then
        for i = 2, #modelPaths do
            if modelPaths[i] == cur then modelLb:Set(i); break end
        end
    end
    lastModelSel = modelLb:Get()
end

local function getBool(k, d)
    local v = C.getOpt(k); if v == nil then return d end
    return v and true or false
end
hlOn:Set(getBool("hl_on", true))
hlHit:Set(getBool("hl_hit", true))
hlKill:Set(getBool("hl_kill", true))
hlHurt:Set(getBool("hl_hurt", true))
hlMiss:Set(getBool("hl_miss", false))
hsOn:Set(getBool("hs_on2", true))
ksOn:Set(getBool("ks_on2", false))
local function setCmb(cmb, k)
    local i = tonumber(C.getOpt(k))
    if i and i >= 1 and i <= #SND_NAMES then cmb:Set(i) end
end
setCmb(hsCmb, "hs_snd2")
setCmb(ksCmb, "ks_snd2")
hsVol:Set(tonumber(C.getOpt("hs_vol2")) or 100)
ksVol:Set(tonumber(C.getOpt("ks_vol2")) or 100)

wmOn:Set(getBool("wm_on", true))
do
    local cur = wmElems:Get()
    local sel = {}
    for i, k in ipairs(WM_PARTS) do
        local v = C.getOpt("wm_" .. k)
        if v == nil then sel[i] = cur[i] and true or nil
        else sel[i] = v and true or nil end
    end
    wmElems:Set(sel)
end
do local p = tonumber(C.getOpt("wm_pos")); if p and p >= 1 and p <= #WM_POS then wmPos:Set(p) end end

rgOn:Set(getBool("rg_on", false))
rgMin:Set(getBool("rg_min", false))
do local p = tonumber(C.getOpt("rg_pen")); if p and p >= 50 and p <= 250 then rgPen:Set(p) end end
do
    local s = C.getOpt("rg_sel")
    if type(s) == "string" and s ~= "" then
        local want = {}
        for id in s:gmatch("%-?%d+") do want[tonumber(id)] = true end
        local sel = {}
        for i, id in ipairs(RG.ids) do if want[id] then sel[i] = true end end
        rgCmb:Set(sel)
    end
end

ncOn:Set(getBool("nc_on", false))
do local p = tonumber(C.getOpt("nc_mode"));  if p and p >= 1 and p <= 2 then ncMode:Set(p) end end
do local p = tonumber(C.getOpt("nc_src"));   if p and p >= 1 and p <= 4 then ncSrc:Set(p) end end
do local p = tonumber(C.getOpt("nc_speed")); if p and p >= 100 and p <= 1000 then ncSpeed:Set(p) end end
do local s = C.getOpt("nc_text"); if type(s) == "string" then ncText:Set(s) end end

vrOn:Set(getBool("vr_on", false))
do local p = tonumber(C.getOpt("vr_mode")); if p and p >= 1 and p <= 3 then vrMode:Set(p) end end

local _frameCount = 0
M:OnFrame(function()
    _frameCount = _frameCount + 1
    pcall(syncCategory)
    pcall(HS.flushSounds)
    pcall(HS.missTick)
    -- Run heavy stuff every 5 frames
    if _frameCount % 5 == 0 then
        pcall(autoFollow)
        pcall(syncSkins)
        pcall(autoApply)
        pcall(syncVm)
        pcall(HS.sync)
    end
    -- Run slow stuff every 30 frames
    if _frameCount % 30 == 0 then
        pcall(persistOpts)
        pcall(syncModel)
        pcall(hlSync)
        pcall(wmSync)
        pcall(rgSync)
        pcall(ncSync)
        pcall(vrSync)
    end
end)

-- Theme tab
local ttab = M:Tab("Theme")
local themeSec = ttab:Section("Colors")
local thAccent = themeSec:ColorPicker("Accent color", { 220, 40, 40, 255 })
local thAccBg  = themeSec:ColorPicker("Accent BG", { 50, 20, 20, 255 })
local thBg     = themeSec:ColorPicker("Background", { 20, 20, 26, 255 })
local thText   = themeSec:ColorPicker("Text color", { 188, 188, 198, 255 })
themeSec:Button("Apply", function()
    local T = M.T
    if not T then M:Error("Theme not available"); return end
    local a = thAccent:Get()
    local b = thAccBg:Get()
    local bg = thBg:Get()
    local tx = thText:Get()
    T.accent     = { a[1], a[2], a[3] }
    T.accent_bg  = { b[1], b[2], b[3], 255 }
    T.notif_info = { a[1], a[2], a[3] }
    T.bg         = { bg[1], bg[2], bg[3], 255 }
    T.bg2        = { math.max(bg[1]-5,0), math.max(bg[2]-5,0), math.max(bg[3]-5,0), 255 }
    T.text       = { tx[1], tx[2], tx[3], 255 }
    C.setOpt("theme_r", a[1]); C.setOpt("theme_g", a[2]); C.setOpt("theme_b", a[3])
    C.setOpt("theme_bg_r", b[1]); C.setOpt("theme_bg_g", b[2]); C.setOpt("theme_bg_b", b[3])
    C.setOpt("theme_main_r", bg[1]); C.setOpt("theme_main_g", bg[2]); C.setOpt("theme_main_b", bg[3])
    C.setOpt("theme_text_r", tx[1]); C.setOpt("theme_text_g", tx[2]); C.setOpt("theme_text_b", tx[3])
    M:Info("Theme applied")
end)
themeSec:Button("Reset to default", function()
    local T = M.T
    if not T then return end
    T.accent     = { 220, 40, 40 }
    T.accent_bg  = { 50, 20, 20, 255 }
    T.notif_info = { 220, 40, 40 }
    T.bg         = { 20, 20, 26, 255 }
    T.bg2        = { 15, 15, 20, 255 }
    T.text       = { 188, 188, 198, 255 }
    thAccent:Set({ 220, 40, 40, 255 })
    thAccBg:Set({ 50, 20, 20, 255 })
    thBg:Set({ 20, 20, 26, 255 })
    thText:Set({ 188, 188, 198, 255 })
    C.setOpt("theme_r", nil); C.setOpt("theme_g", nil); C.setOpt("theme_b", nil)
    C.setOpt("theme_bg_r", nil); C.setOpt("theme_bg_g", nil); C.setOpt("theme_bg_b", nil)
    C.setOpt("theme_main_r", nil); C.setOpt("theme_main_g", nil); C.setOpt("theme_main_b", nil)
    C.setOpt("theme_text_r", nil); C.setOpt("theme_text_g", nil); C.setOpt("theme_text_b", nil)
    M:Info("Theme reset")
end)

do
    local T = M.T
    if T then
        local tr = C.getOpt("theme_r")
        local tg = C.getOpt("theme_g")
        local tb = C.getOpt("theme_b")
        if tr and tg and tb then
            T.accent = { tr, tg, tb }
            T.notif_info = { tr, tg, tb }
            thAccent:Set({ tr, tg, tb, 255 })
        end
        local br = C.getOpt("theme_bg_r")
        local bgg = C.getOpt("theme_bg_g")
        local bb = C.getOpt("theme_bg_b")
        if br and bgg and bb then
            T.accent_bg = { br, bgg, bb, 255 }
            thAccBg:Set({ br, bgg, bb, 255 })
        end
        local mr = C.getOpt("theme_main_r")
        local mg = C.getOpt("theme_main_g")
        local mb = C.getOpt("theme_main_b")
        if mr and mg and mb then
            T.bg  = { mr, mg, mb, 255 }
            T.bg2 = { math.max(mr-5,0), math.max(mg-5,0), math.max(mb-5,0), 255 }
            thBg:Set({ mr, mg, mb, 255 })
        end
        local xr = C.getOpt("theme_text_r")
        local xg = C.getOpt("theme_text_g")
        local xb = C.getOpt("theme_text_b")
        if xr and xg and xb then
            T.text = { xr, xg, xb, 255 }
            thText:Set({ xr, xg, xb, 255 })
        end
    end
end

-- ============================================
-- EXTRA FEATURES
-- ============================================

-- AllowListeners for stats/bomb
pcall(function()
    pcall(function() client.AllowListener("player_death") end)
    pcall(function() client.AllowListener("bomb_planted") end)
    pcall(function() client.AllowListener("bomb_defused") end)
    pcall(function() client.AllowListener("bomb_exploded") end)
    pcall(function() client.AllowListener("round_start") end)
end)

-- Night Mode (disabled - causes crash)
local nightMode = false
local function applyNight(on) end

-- Misc tab additions
local ntabMisc = ntab

-- Add to OnFrame for bomb timer drawing
M:OnFrame(function(ui)
    -- Bomb Timer HUD
    if BOMB.planted then
        local now = globals.RealTime and globals.RealTime() or os.clock()
        local elapsed = now - BOMB.time
        local remaining = math.max(0, BOMB.maxTime - elapsed)
        if remaining > 0 then
            local sw, sh = 0, 0
            pcall(function() sw, sh = draw.GetScreenSize() end)
            if sw > 0 then
                local bw, bh = 200, 30
                local bx, by = (sw - bw) / 2, sh - 80
                local frac = remaining / BOMB.maxTime
                local col = frac > 0.3 and { 220, 40, 40, 200 } or { 255, 60, 60, 255 }
                -- background
                draw.Color(20, 20, 26, 180)
                draw.FilledRect(math.floor(bx), math.floor(by), math.floor(bx + bw), math.floor(by + bh))
                -- bar
                draw.Color(col[1], col[2], col[3], col[4])
                draw.FilledRect(math.floor(bx + 2), math.floor(by + 2), math.floor(bx + 2 + (bw - 4) * frac), math.floor(by + bh - 2))
                -- text
                draw.Color(255, 255, 255, 255)
                draw.Text(math.floor(bx + 8), math.floor(by + 8), string.format("C4 %s - %.1fs", BOMB.site, remaining))
            end
        else
            BOMB.planted = false
        end
    end
end)

-- Skin Presets
local PRESETS = {}

local function savePreset(name)
    if not name or name == "" then return end
    local data = {}
    for def, c in pairs(C.getCfg and {} or {}) do
        data[def] = c
    end
    -- Save current config as preset
    PRESETS[name] = C and pcall(function()
        local cfg = {}
        for _, it in ipairs(C.items) do
            local c = C.getCfg(it.def)
            if c then cfg[it.def] = c end
        end
        PRESETS[name] = cfg
    end)
    C.setOpt("preset_" .. name, "saved")
    M:Info("Preset '" .. name .. "' saved")
end

local function loadPreset(name)
    if not PRESETS[name] then M:Error("Preset not found"); return end
    for def, c in pairs(PRESETS[name]) do
        local it = nil
        for _, item in ipairs(C.items) do
            if item.def == def then it = item; break end
        end
        if it then C.apply(it, c.paint, c.wear, c.seed) end
    end
    M:Info("Preset '" .. name .. "' loaded")
end

-- Misc sub-tabs: Spammer, Anti-AFK, Reconnect
local subSpam = ntab:Sub("Spammer")
local spamSec = subSpam:Section("Spammer")
spamOn = spamSec:Checkbox("Enabled", false)
spamMode = spamSec:Combo("Mode", { "Fixed text", "Multi-line" }, 1)
spamText = spamSec:Input("Message", "", "type your msg here")
spamDelay = spamSec:Slider("Delay (s)", 1.0, 0.1, 5.0, 0.1, "%.1f")
spamChat = spamSec:Combo("Chat type", { "All Chat", "Team Chat" }, 1)
spamVac = spamSec:Checkbox("Auto VAC msg", false)
spamVacRound = spamSec:Slider("VAC at round", 12, 1, 30, 1)
spamSec:Button("Send VAC now", function()
    local vacMsg = "gg" .. string.rep("\xE1\x85\xA0", 40) .. "VACNET has detected a cheater and ended the match. This match will not affect you."
    pcall(function() client.ChatSay(vacMsg) end)
    M:Info("VAC msg sent")
end)

pcall(function() client.AllowListener("round_end") end)

local subAFK = ntab:Sub("Anti-AFK")
local afkSec = subAFK:Section("Anti-AFK")
local afkOn = afkSec:Checkbox("Enabled", false)
afkSec:Button("Reset stats", function()
    STATS.kills = 0; STATS.deaths = 0; STATS.hits = 0
    STATS.shots = 0; STATS.headshots = 0; STATS.dmg = 0
    M:Info("Stats reset")
end)

local _afkDir = 1
local _afkNextSwitch = 0
pcall(function()
    callbacks.Register("CreateMove", "TROPA DO PINO PRETO_AFK", function(cmd)
        if not afkOn:Get() then return end
        local now = 0
        pcall(function() now = globals.RealTime() end)
        if not now or now == 0 then pcall(function() now = os.clock() end) end
        if now >= _afkNextSwitch then
            _afkDir = _afkDir * -1
            _afkNextSwitch = now + 0.3 + math.random() * 0.9
        end
        pcall(function() cmd:SetSideMove(250 * _afkDir) end)
    end)
end)

local subRB = ntab:Sub("Reconnect")
local rbSec = subRB:Section("Reconnect Bypass")
rbSec:Button("Enable (block Steam)", function()
    pcall(function()
        pcall(function() ffi.cdef[[ void* ShellExecuteA(void*, const char*, const char*, const char*, const char*, int); ]] end)
        local Shell32 = ffi.load("Shell32")
        local cmd = 'New-NetFirewallRule -DisplayName "TPP_Block" -Direction Outbound -Action Block -Program "C:\\Program Files (x86)\\Steam\\steam.exe"'
        Shell32.ShellExecuteA(nil, "runas", "powershell.exe", '-ExecutionPolicy Bypass -WindowStyle Hidden -Command "' .. cmd .. '"', nil, 0)
    end)
    M:Info("Steam blocked - you can reconnect")
end)
rbSec:Button("Disable (unblock Steam)", function()
    pcall(function()
        local Shell32 = ffi.load("Shell32")
        local cmd = 'Remove-NetFirewallRule -DisplayName "TPP_Block"'
        Shell32.ShellExecuteA(nil, "runas", "powershell.exe", '-ExecutionPolicy Bypass -WindowStyle Hidden -Command "' .. cmd .. '"', nil, 0)
    end)
    M:Info("Steam unblocked")
end)

-- Spammer Draw logic
M:OnFrame(function()
    if not spamOn:Get() then return end
    local now = 0
    pcall(function() now = globals.RealTime() end)
    if not now or now == 0 then pcall(function() now = os.clock() end) end
    if (now - _spamLastTime) < spamDelay:Get() then return end
    local mode = spamMode:Get()
    if mode == 1 then
        local msg = spamText:Get()
        if msg ~= "" then
            pcall(function()
                if spamChat:Get() == 1 then client.ChatSay(msg)
                else client.ChatTeamSay(msg) end
            end)
        end
    elseif mode == 2 then
        local msg = spamText:Get()
        local lines = {}
        for line in (msg or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
        if #lines > 0 then
            if _spamMultiIdx > #lines then _spamMultiIdx = 1 end
            pcall(function()
                if spamChat:Get() == 1 then client.ChatSay(lines[_spamMultiIdx])
                else client.ChatTeamSay(lines[_spamMultiIdx]) end
            end)
            _spamMultiIdx = _spamMultiIdx + 1
        end
    end
    _spamLastTime = now
end)

M:Build({ w = 950, h = 620, x = 200, y = 100 })

-- Separate Draw callback for sound flush (must run every frame)
pcall(function()
    callbacks.Register("Draw", "TROPA DO PINO PRETO_SndFlush", function()
        pcall(HS.flushSounds)
        pcall(HS.missTick)
    end)
end)
