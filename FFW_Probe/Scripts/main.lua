--[[
    FFW_Probe  -  Far Far West reflection dumper
    ------------------------------------------------
    Development helper for the FFW_Cheat mod. It walks the UObject array of the
    running game and writes every UClass together with its properties, functions
    and (for gameplay relevant classes) the class default values to:

        <Game>/FarFarWest/Binaries/Win64/ue4ss/Mods/FFW_Probe/ffw_sdk_dump.txt

    Nothing is modified. Delete the mod folder when you are done with it.
]]

local OUT_PATH = "Mods/FFW_Probe/ffw_sdk_dump.txt"

local fh = nil
local function openOut()
    local ok, f = pcall(io.open, OUT_PATH, "w")
    if ok and f then
        fh = f
        return true
    end
    return false
end

local function w(line)
    if fh then
        fh:write(line, "\n")
    else
        print(line)
    end
end

local function flush()
    if fh then fh:flush() end
end

local function safe(fn, ...)
    local res = { pcall(fn, ...) }
    if res[1] then
        return true, table.unpack(res, 2)
    end
    return false, nil
end

local PROP_TYPES = {
    "ObjectProperty", "ObjectPtrProperty", "WeakObjectProperty", "ClassProperty",
    "Int8Property", "Int16Property", "IntProperty", "Int64Property",
    "UInt16Property", "UIntProperty", "UInt64Property", "ByteProperty",
    "FloatProperty", "DoubleProperty", "BoolProperty", "NameProperty",
    "StrProperty", "TextProperty", "EnumProperty", "ArrayProperty",
    "MapProperty", "SetProperty", "StructProperty", "DelegateProperty",
    "MulticastDelegateProperty", "InterfaceProperty", "FieldPathProperty",
}

local function propType(p)
    for _, t in ipairs(PROP_TYPES) do
        local ok, is = pcall(function() return p:IsA(t) end)
        if ok and is then return t end
    end
    return "Unknown"
end

-- Classes whose default values are worth recording.
local VALUE_KEYWORDS = {
    "Player", "Character", "Pawn", "Health", "Damage", "Weapon", "Ammo",
    "Stat", "Gold", "Soul", "Currency", "Buff", "Tweak", "Inventory",
    "Item", "Loot", "Progress", "Save", "GameState", "GameMode",
    "Difficulty", "Spell", "Reload", "Dash", "Jump",
}

local function interesting(name)
    for _, k in ipairs(VALUE_KEYWORDS) do
        if string.find(name, k, 1, true) then return true end
    end
    return false
end

local function fmtValue(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then
        return tostring(v)
    end
    if t == "userdata" or t == "table" then
        local ok, s = pcall(function() return v:GetFullName() end)
        if ok and type(s) == "string" then return s end
    end
    return "<" .. t .. ">"
end

local classCount, propCount, funcCount = 0, 0, 0

local function dumpClass(cls)
    local okName, shortName = safe(function() return cls:GetFName():ToString() end)
    if not okName or not shortName then return end

    local okFull, fullName = safe(function() return cls:GetFullName() end)
    if not okFull then fullName = "?" end

    local super = "?"
    local okSuper, s = safe(function()
        local sup = cls:GetSuperStruct()
        if sup and sup:IsValid() then return sup:GetFullName() end
        return nil
    end)
    if okSuper and s then super = s end

    classCount = classCount + 1
    w("")
    w("CLASS " .. fullName)
    w("  SHORT " .. shortName)
    w("  SUPER " .. super)

    local okProps = pcall(function()
        cls:ForEachProperty(function(p)
            local pok, pn = pcall(function() return p:GetFName():ToString() end)
            if pok and pn then
                local t = propType(p)
                propCount = propCount + 1
                w(string.format("  PROP %s : %s", pn, t))
            end
        end)
    end)
    if not okProps then w("  PROP <ForEachProperty failed>") end

    local okFuncs = pcall(function()
        cls:ForEachFunction(function(f)
            local fok, fn = pcall(function() return f:GetFName():ToString() end)
            if fok and fn then
                funcCount = funcCount + 1
                local flags = ""
                local fok2, fl = pcall(function() return f:GetFunctionFlags() end)
                if fok2 and fl then flags = string.format(" flags=0x%X", fl) end
                w(string.format("  FUNC %s%s", fn, flags))
            end
        end)
    end)
    if not okFuncs then w("  FUNC <ForEachFunction failed>") end

    -- Default values, for classes that look gameplay relevant.
    if interesting(shortName) then
        local okCdo, cdo = safe(function() return cls:GetCDO() end)
        if okCdo and cdo then
            pcall(function()
                cls:ForEachProperty(function(p)
                    local pok, pn = pcall(function() return p:GetFName():ToString() end)
                    if not pok or not pn then return end
                    local t = propType(p)
                    if t == "FloatProperty" or t == "DoubleProperty" or t == "IntProperty"
                        or t == "Int64Property" or t == "ByteProperty" or t == "BoolProperty"
                        or t == "NameProperty" or t == "StrProperty" then
                        local vok, v = pcall(function() return cdo:GetPropertyValue(pn) end)
                        if vok then w(string.format("  DEF  %s = %s", pn, fmtValue(v))) end
                    end
                end)
            end)
        end
    end
    flush()
end

local function isClassObject(obj)
    local ok, cn = safe(function() return obj:GetClass():GetFName():ToString() end)
    if not ok or not cn then return false end
    return cn == "Class"
        or cn == "BlueprintGeneratedClass"
        or cn == "WidgetBlueprintGeneratedClass"
        or cn == "AnimBlueprintGeneratedClass"
        or string.find(cn, "GeneratedClass", 1, true) ~= nil
end

local function runDump()
    if not openOut() then
        print("[FFW_Probe] could not open " .. OUT_PATH .. " - falling back to log output")
    end
    w("=== FFW_Probe dump ===")

    local probe = CreateInvalidObject and "CreateInvalidObject" or "?"
    w("probe_api=" .. probe)

    local okPC, pc = safe(function() return UEHelpers.GetPlayerController() end)
    w("PlayerController=" .. (okPC and pc and tostring(pc:GetFullName()) or "<none>"))
    local okPawn, pawn = safe(function() return UEHelpers.GetPlayerPawn() end)
    w("PlayerPawn=" .. (okPawn and pawn and tostring(pawn:GetFullName()) or "<none>"))
    local okW, world = safe(function() return UEHelpers.GetWorld() end)
    w("World=" .. (okW and world and tostring(world:GetFullName()) or "<none>"))
    if okPawn and pawn and pawn:IsValid() then
        local okC, c = safe(function() return pawn:GetClass():GetFullName() end)
        w("PlayerPawnClass=" .. tostring(c))
    end

    ForEachUObject(function(obj, chunk, idx)
        if isClassObject(obj) then
            local ok = pcall(dumpClass, obj)
            if not ok then
                -- skip broken classes silently
            end
        end
    end)

    w("")
    w(string.format("=== totals: classes=%d properties=%d functions=%d ===",
        classCount, propCount, funcCount))
    flush()
    if fh then fh:close() fh = nil end
    print(string.format("[FFW_Probe] done: %d classes, %d properties, %d functions",
        classCount, propCount, funcCount))
end

-- Give the game time to boot, then dump on the game thread.
ExecuteWithDelay(30000, function()
    ExecuteInGameThread(runDump)
end)
