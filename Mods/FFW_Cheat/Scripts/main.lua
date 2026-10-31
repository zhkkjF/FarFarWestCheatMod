--[[
    FFW_Cheat  -  Far Far West cheat mod for UE4SS
    ==================================================
    Built from a reflection dump of Far Far West (UE 5.8, shipping).

    Safety model
    ------------
    Every function in here was observed working in a real session before it was
    kept. Anything whose blueprint signature could not be verified was removed,
    because a wrong call into UE4SS's native layer raises an access violation
    that Lua's pcall cannot catch (that is what crashed the game on 2026-10-31).

    Rules followed below:
      * only write properties that exist, after reading their current value type
      * only call zero-argument blueprint functions that were seen working
      * always re-check IsValid() immediately before touching an object
      * no background loops faster than the 250 ms cheat tick

    Classes used:
        BP_Player_C          jumpsLeft / currentDashLeft / maxDash / buffMoveSpeed / buffGravity
        BP_PlayerState_C     invincible / playerHeal / playerMaxHeal / F_RefillAllAmmo_OwningClient
        AC_PlayerState_Shield_C   shieldPoints / shieldPointsMax
        BP_GameState_C       pickedUpGolds / pickedUpSouls / pickedUpUranium / mapRevealed
        BP_Enemy_C           F_DestroyEnemy
]]

local CONFIG = {
    tickMs = 250,             -- how often active toggles re-apply themselves
    godKeepsHealth = true,    -- also top up health and shield while god mode is on
    jumps = 9,                -- jumpsLeft / currentDashLeft / maxDash while F3 is on
    dashes = 9,
    speedBuff = 1.0,          -- buffMoveSpeed offset, 0.0 = vanilla (additive)
    gravityBuff = -0.65,      -- buffGravity offset, negative = lighter
    goldAmount = 10000,
    soulAmount = 10000,
    uraniumAmount = 250,
    maxEnemiesPerSweep = 200,
}

-- Zero-argument calls that were verified working in a live session. Turning this
-- off leaves the mod purely property-based (safest possible configuration).
local ALLOW_BLUEPRINT_CALLS = true

--##############################################################################
-- helpers
--##############################################################################

--- When a console command is being executed this holds the FOutputDevice of the
--- console, so feedback is visible where the user typed it, not only in the log.
local lastOut = nil

local function log(fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok then text = tostring(fmt) end
    print("[FFW_Cheat] " .. text)
    local ar = lastOut
    if ar ~= nil then
        pcall(function() ar:Log(text) end)
    end
end

--- A wrapper can outlive the object it points at; always re-check before use.
local function alive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function nameOf(obj)
    if obj == nil then return nil end
    local ok, n = pcall(function() return obj:GetFullName() end)
    if ok and n then return n end
    return nil
end

local cache = {}

local function find(key, className)
    local hit = cache[key]
    if alive(hit) then return hit end
    cache[key] = nil
    local found = FindFirstOf(className)
    if alive(found) then
        cache[key] = found
        return found
    end
    return nil
end

local function getProp(obj, name)
    if not alive(obj) then return nil end
    local ok, value = pcall(function() return obj:GetPropertyValue(name) end)
    if ok then return value end
    return nil
end

local function getNumber(obj, name, default)
    local v = getProp(obj, name)
    if type(v) == "number" then return v end
    return default
end

local function getBool(obj, name)
    local v = getProp(obj, name)
    if type(v) == "boolean" then return v end
    return nil
end

--- Writes only when the property already exists and its Lua type is known.
local function setProp(obj, name, want)
    if not alive(obj) then return false end
    local okCur, cur = pcall(function() return obj:GetPropertyValue(name) end)
    if not okCur then return false end

    local value = want
    local curType = type(cur)
    if curType == "boolean" then
        value = (want ~= false and want ~= 0)
    elseif curType == "number" then
        if type(want) == "boolean" then
            value = want and 1 or 0
        elseif type(want) ~= "number" then
            return false
        end
    else
        -- nil (null object reference) or a struct/object: do not touch it
        return false
    end

    if pcall(function() obj:SetPropertyValue(name, value) end) then return true end
    return (pcall(function() obj[name] = value end))
end

--- Only zero-argument calls are allowed; anything else was not verified and is
--- exactly what produced access violations before.
local function callSimple(obj, name)
    if not ALLOW_BLUEPRINT_CALLS then return false end
    if not alive(obj) then return false end
    local okFn, fn = pcall(function() return obj[name] end)
    if not okFn or fn == nil then return false end
    return (pcall(fn, obj))
end

--##############################################################################
-- game objects
--##############################################################################

local function getPawn()
    local list = FindAllOf("BP_Player_C")
    if list then
        local fallback
        for _, p in pairs(list) do
            if alive(p) then
                if fallback == nil then fallback = p end
                if getBool(p, "IsLocalController") == true then return p end
            end
        end
        if fallback then return fallback end
    end
    return find("pawn", "BP_Player_C")
end

local function getPlayerState(pawn)
    if pawn then
        local ps = getProp(pawn, "localPlayerState")
        if alive(ps) then return ps end
    end
    return find("ps", "BP_PlayerState_C")
end

local function getGameState()
    return find("gs", "BP_GameState_C")
end

local function getShield(playerState)
    if playerState == nil then return nil end
    local shield = getProp(playerState, "AC_PlayerState_Shield")
    if alive(shield) then return shield end
    return nil
end

--##############################################################################
-- cheats
--##############################################################################

local state = { god = false, ammo = false, movement = false, speed = false, gravity = false }

local function applyGodMode()
    local ps = getPlayerState(getPawn())
    if ps == nil then return false end

    setProp(ps, "invincible", true)

    local maxHeal = getNumber(ps, "playerMaxHeal")
    if CONFIG.godKeepsHealth and maxHeal and maxHeal > 0 then
        setProp(ps, "playerHeal", maxHeal)
        local shield = getShield(ps)
        if shield then
            local maxShield = getNumber(shield, "shieldPointsMax")
            if maxShield and maxShield > 0 then
                setProp(shield, "shieldPoints", maxShield)
            end
        end
    end
    return true
end

local function clearGodMode()
    local ps = getPlayerState(getPawn())
    if ps then setProp(ps, "invincible", false) end
end

local function applyMovement()
    local pawn = getPawn()
    if pawn == nil then return false end
    setProp(pawn, "jumpsLeft", CONFIG.jumps)
    setProp(pawn, "currentDashLeft", CONFIG.dashes)
    setProp(pawn, "maxDash", CONFIG.dashes)
    return true
end

local function applyBuff(prop, value, refreshFn)
    local pawn = getPawn()
    if pawn == nil then return false end
    local ok = setProp(pawn, prop, value)
    if refreshFn then callSimple(pawn, refreshFn) end
    return ok
end

local function applySpeed()   return applyBuff("buffMoveSpeed", CONFIG.speedBuff, "F_UpdateSpeed") end
local function clearSpeed()   return applyBuff("buffMoveSpeed", 0.0, "F_UpdateSpeed") end
local function applyGravity() return applyBuff("buffGravity", CONFIG.gravityBuff, "F_UpdateGravity") end
local function clearGravity() return applyBuff("buffGravity", 0.0, "F_UpdateGravity") end

local function refillAmmo()
    local ps = getPlayerState(getPawn())
    if ps == nil then return false end
    return callSimple(ps, "F_RefillAllAmmo_OwningClient")
end

local function addCurrency(prop, amount, refreshFn)
    local gs = getGameState()
    if gs == nil then
        log("no game state yet - start a run first")
        return false
    end
    local before = getNumber(gs, prop, 0) or 0
    if not setProp(gs, prop, before + amount) then
        log("could not write %s", prop)
        return false
    end
    if refreshFn then callSimple(gs, refreshFn) end
    log("%s: %d -> %d", prop, math.floor(before), math.floor(before + amount))
    return true
end

local function addGold(amount)    return addCurrency("pickedUpGolds", amount or CONFIG.goldAmount, "F_UpdateGolds") end
local function addSouls(amount)   return addCurrency("pickedUpSouls", amount or CONFIG.soulAmount, "F_UpdateSouls") end
local function addUranium(amount) return addCurrency("pickedUpUranium", amount or CONFIG.uraniumAmount, "F_UpdateUranium") end

local function fullHeal()
    local ps = getPlayerState(getPawn())
    if ps == nil then return false end
    local maxHeal = getNumber(ps, "playerMaxHeal")
    if maxHeal then setProp(ps, "playerHeal", maxHeal) end
    local shield = getShield(ps)
    if shield then
        local maxShield = getNumber(shield, "shieldPointsMax")
        if maxShield then setProp(shield, "shieldPoints", maxShield) end
    end
    log("healed to %s", tostring(maxHeal))
    return true
end

local function killEnemies()
    local enemies = FindAllOf("BP_Enemy_C")
    if not enemies then
        log("no enemies found")
        return false
    end
    local killed = 0
    for _, enemy in pairs(enemies) do
        if killed >= CONFIG.maxEnemiesPerSweep then break end
        -- re-checked right before the call: a previous iteration may have killed it
        if alive(enemy) and callSimple(enemy, "F_DestroyEnemy") then
            killed = killed + 1
        end
    end
    log("enemies destroyed: %d", killed)
    return killed > 0
end

local function revealMap()
    local gs = getGameState()
    if gs == nil then return false end
    setProp(gs, "mapRevealed", true)
    log("map revealed")
    return true
end

--- Run fn on the game thread after a delay.
local function defer(fn, ms)
    ExecuteWithDelay(ms or 300, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then log("error: %s", tostring(err)) end
        end)
    end)
end

--##############################################################################
-- freecam  (the game's own BP_Freecam_C pawn)
--##############################################################################

local function findFreecam()
    local ps = getPlayerState(getPawn())
    if ps then
        local fc = getProp(ps, "freecamPawn")
        if alive(fc) then return fc end
    end
    local fc = FindFirstOf("BP_Freecam_C")
    if alive(fc) then return fc end
    return nil
end

--- Both entry points take zero arguments. Only these two are used; the engine
--- cheat-manager "fly" experiment (SetMovementMode + a 40 ms re-apply loop) is
--- what crashed the game on 2026-10-31 and is not coming back.
local function toggleFreecam()
    local ps = getPlayerState(getPawn())
    if ps == nil then
        log("freecam: no player state yet (start a run first)")
        return false
    end

    if findFreecam() then
        if callSimple(ps, "F_RemoveFreecam_Server") then
            log("freecam: OFF")
            return true
        end
        log("freecam: F_RemoveFreecam_Server failed")
        return false
    end

    if callSimple(ps, "F_SpawnFreecam_Server") then
        log("freecam: requested")
        defer(function()
            if findFreecam() then
                log("freecam: ON - WASD + mouse to fly, F12 to come back")
            else
                log("freecam: the game did not spawn it")
            end
        end, 700)
        return true
    end
    log("freecam: F_SpawnFreecam_Server failed")
    return false
end

--##############################################################################
-- the game's own debug menu
--##############################################################################

--- In a normal session BP_Manager_Cheats_C is not placed in the level, so the old
--- version gave up after one FindFirstOf. These three zero-argument entry points
--- are what actually works once a run is going (and after freecam has been used),
--- so they are tried in order and verified by looking for the widget instance.
local MENU_STEPS = {
    {
        label = "player controller",
        fn = function()
            local pc = find("pc", "BP_PlayerController_C")
            if pc == nil then return false end
            return callSimple(pc, "F_OpenCheatsMenu")
        end,
    },
    {
        label = "menu manager",
        fn = function()
            local mm = find("menu", "BP_Manager_Menu_C")
            if mm == nil then return false end
            return callSimple(mm, "F_OpenCheat")
        end,
    },
    {
        label = "cheat manager",
        fn = function()
            local cm = find("cheats", "BP_Manager_Cheats_C")
            if cm == nil then return false end
            return callSimple(cm, "F_OpenCheatsMenu")
        end,
    },
}

local menuStep, menuBusy = 0, false

-- assigned further down, next to the translation table
local localizeSoon = nil

local function menuWidget()
    local w = FindFirstOf("UI_CheatMenu_C")
    if alive(w) then return w end
    return nil
end

local function menuAdvance()
    if menuWidget() then
        log("cheat menu is open")
        menuBusy = false
        if localizeSoon then localizeSoon() end
        return
    end

    menuStep = menuStep + 1
    local step = MENU_STEPS[menuStep]
    if step == nil then
        log("cheat menu did not open - none of the %d entry points worked", #MENU_STEPS)
        menuBusy = false
        return
    end

    local ok, called = pcall(step.fn)
    log("menu step %d/%d (%s): %s", menuStep, #MENU_STEPS, step.label,
        ok and (called and "called" or "entry point not available")
        or ("error " .. tostring(called)))
    defer(menuAdvance, 350)
end

local function openCheatMenu()
    if menuBusy then
        log("already trying to open the cheat menu")
        return false
    end
    menuBusy, menuStep = true, 0
    defer(menuAdvance, 0)
    return true
end

--- Widget existence is not the same as "visible": the menu closes itself through
--- its own back button and leaves the object alive, so visibility decides.
local function menuVisible()
    local w = menuWidget()
    if w == nil then return false end
    local visible = false
    pcall(function() visible = (w:IsInViewport() == true) end)
    return visible
end

--- The menu is built for mouse input: while it is open the controller is in a UI
--- input mode, and simply hiding the widget does not hand the keyboard back. This
--- puts the controller back into "game only" state.
local function restoreGameInput()
    local pc = find("pc", "BP_PlayerController_C") or find("pcBase", "PlayerController")
    if pc == nil then
        log("input restore: no player controller yet")
        return false
    end
    pcall(function() pc:SetIgnoreMoveInput(false) end)
    pcall(function() pc:SetIgnoreLookInput(false) end)
    pcall(function() pc:SetPause(false) end)
    setProp(pc, "bShowMouseCursor", false)
    log("input restored to the game")
    return true
end

local function closeCheatMenu()
    local closed = false
    local mm = find("menu", "BP_Manager_Menu_C")
    if mm ~= nil and callSimple(mm, "F_CloseCheat") then
        log("cheat menu: closed (menu manager)")
        closed = true
    end

    local w = menuWidget()
    if w ~= nil then
        if not closed and callSimple(w, "F_Close") then
            log("cheat menu: closed (widget)")
            closed = true
        elseif not closed then
            pcall(function() w:RemoveFromParent() end)
            log("cheat menu: removed from screen")
            closed = true
        end
    end

    restoreGameInput()
    return closed
end

--- Full recovery for the "keyboard does nothing" case: leave freecam if it is still
--- active (the camera moves, the character does not) and hand input back.
local function recoverControl()
    local ps = getPlayerState(getPawn())
    if ps ~= nil and findFreecam() ~= nil then
        if callSimple(ps, "F_RemoveFreecam_Server") then
            log("freecam: OFF")
        end
    end
    return restoreGameInput()
end

--- ffw menu toggles: closes when visible, re-shows a stale widget, else opens.
local function toggleCheatMenu()
    if menuVisible() then
        return closeCheatMenu()
    end

    local w = menuWidget()
    if w ~= nil then
        if pcall(function() w:AddToViewport(0) end) then
            log("cheat menu: shown again")
            if localizeSoon then localizeSoon() end
            return true
        end
    end
    return openCheatMenu()
end

--##############################################################################
-- chinese labels for the debug menu
--##############################################################################

-- Keyed by the exact english string the widget shows, collected from the widget
-- tree template of /Game/Interfaces/UI_CheatMenu. Anything not listed is reported
-- once as "ZH missing" so the table can be completed without guessing.
local ZH = {
    -- section headers
    ["ITEMS"] = "物品",
    ["PRIMARY WEAPONS"] = "主武器",
    ["MELEE WEAPONS"] = "近战武器",
    ["SIDEARM WEAPONS"] = "副手武器",
    ["CACTUS SPELLS"] = "仙人掌法术",
    ["ACID SPELLS"] = "酸液法术",
    ["VOODOO SPELLS"] = "巫毒法术",
    ["ELEC SPELLS"] = "电系法术",
    ["FIRE SPELLS"] = "火系法术",
    ["FROST SPELLS"] = "冰系法术",
    ["LOBBY SHOPS"] = "大厅商店",
    ["IN GAME CHEATS"] = "局内作弊",
    ["SAVE MANIPULATION"] = "存档修改",
    ["SPAWN CRYPTIC"] = "生成 Cryptic",
    ["RECORDING"] = "录制",

    -- lobby shops
    ["Spell shop"] = "法术商店",
    ["Weapon shop"] = "武器商店",
    ["Hero shop"] = "英雄商店",
    ["Skin shop"] = "皮肤商店",
    ["Open Journal"] = "打开日志",
    ["List inventory"] = "列出背包",
    ["List item joker"] = "列出小丑道具",
    ["List Challenges"] = "列出挑战",
    ["Max 4 players"] = "队伍上限 4 人",
    ["Max 20 players"] = "队伍上限 20 人",

    -- in game cheats
    ["Teleport to objective"] = "传送到目标点",
    ["Teleport to boss"] = "传送到 Boss",
    ["Spawn boss"] = "召唤 Boss",
    ["Call extraction"] = "呼叫撤离",
    ["Finish active quest"] = "完成当前委托",
    ["Start storm"] = "触发风暴",
    ["Reveal map"] = "地图全开",
    ["Add disturbance level"] = "增加扰动等级",
    ["Spawn modifier"] = "生成修正",
    ["Kill all enemies"] = "秒杀全部敌人",
    ["End Game"] = "结束本局",
    ["Invincibility toggle"] = "无敌开关",
    ["Refill ammo"] = "补满弹药",
    ["Add 10 Uranium"] = "加 10 铀矿",
    ["Reset spell cooldowns"] = "重置法术冷却",
    ["Enemy AI toggle"] = "敌人 AI 开关",
    ["Open shader map"] = "打开着色器编译图",

    -- save manipulation
    ["Reset save file"] = "重置存档",
    ["Max lvl save"] = "满级存档",
    ["Unlock all difficulties"] = "解锁全部难度",
    ["Unlock all challenges"] = "解锁全部挑战",
    ["Gamescom save"] = "Gamescom 存档",
    ["Add 10.000 weapon xp"] = "武器 +10000 经验",
    ["Add 1000 Hero XP"] = "英雄 +1000 经验",
    ["Add 1000 Gold"] = "金币 +1000",
    ["Add 100 Tickets"] = "门票 +100",
    ["Add 500 Souls"] = "灵魂 +500",
    ["Add 1000 Spell XP"] = "法术 +1000 经验",
    ["Restart 1 challenge"] = "重开 1 个挑战",

    -- recording
    ["Freecam"] = "自由视角",
    ["Rotate atmo"] = "切换昼夜氛围",
}

local zhMissing = {}
local zhDone = {}

local function widgetText(widget)
    -- buttons keep the caption in an FText property, plain labels in the same one
    local ok, value = pcall(function() return widget:GetPropertyValue("Text") end)
    if ok and value ~= nil then
        local okS, s = pcall(function() return value:ToString() end)
        if okS and type(s) == "string" then return s end
    end
    local okG, t = pcall(function() return widget:GetText() end)
    if okG and t ~= nil then
        local okS2, s2 = pcall(function() return t:ToString() end)
        if okS2 then return s2 end
    end
    return nil
end

local function applyText(widget, zh)
    local okF, ft = pcall(function() return FText(zh) end)
    if not okF or ft == nil then return false end
    -- UI_Template_Button_C has its own setter; TextBlock has SetText
    if pcall(function() widget:F_SetText(ft) end) then return true end
    if pcall(function() widget:SetText(ft) end) then return true end
    return false
end

local function walkWidgets(root, depth, visit)
    if root == nil or depth > 12 then return end
    visit(root)
    local okCount, count = pcall(function() return root:GetChildrenCount() end)
    if not okCount or type(count) ~= "number" or count <= 0 then return end
    for i = 0, count - 1 do
        local okChild, child = pcall(function() return root:GetChildAt(i) end)
        if okChild and child ~= nil then
            local c = child
            pcall(function() local v = child:get(); if v ~= nil then c = v end end)
            walkWidgets(c, depth + 1, visit)
        end
    end
end

--- A button is a UserWidget with its own WidgetTree, so if its setter refuses the
--- text, dig into that tree and set the TextBlock directly.
local function applyTextDeep(widget, zh)
    if applyText(widget, zh) then return true end
    local tree = getProp(widget, "WidgetTree")
    if tree == nil then return false end
    local root = getProp(tree, "RootWidget")
    if root == nil then return false end
    local done = false
    walkWidgets(root, 0, function(child)
        local cls = nil
        pcall(function() cls = child:GetClass():GetFName():ToString() end)
        if cls == "TextBlock" and applyText(child, zh) then done = true end
    end)
    return done
end

--- Walk one widget tree and swap every label we have a translation for.
local function translateRoot(root)
    if root == nil then return 0 end
    local changed = 0
    walkWidgets(root, 0, function(widget)
        local text = widgetText(widget)
        if text == nil or text == "" then return end
        if zhDone[text] then return end

        local zh = ZH[text]
        if zh ~= nil then
            if applyTextDeep(widget, zh) then
                zhDone[zh] = true
                changed = changed + 1
            end
        elseif not zhMissing[text] then
            zhMissing[text] = true
            log("ZH missing: [%s]", text)
        end
    end)
    return changed
end

local function rootOf(widget)
    if widget == nil then return nil end
    local tree = getProp(widget, "WidgetTree")
    if tree == nil then return nil end
    return getProp(tree, "RootWidget")
end

--- Walk the live cheat menu instance.
local function translateCheatMenu()
    return translateRoot(rootOf(menuWidget()))
end

--- Also translate the class template, so a menu built afterwards starts chinese
--- instead of flashing english for a frame. Runs at startup, which doubles as a
--- self-test: the log reports how many labels were accepted.
local function translateTemplate()
    local cls = StaticFindObject("/Game/Interfaces/UI_CheatMenu.UI_CheatMenu_C")
    if cls == nil then return 0 end
    return translateRoot(rootOf(cls))
end

--- The widget builds its children on construct, so retry a few times after opening.
localizeSoon = function()
    for _, delay in ipairs({ 250, 700, 1500, 2600 }) do
        defer(function()
            if menuWidget() == nil then return end
            local n = translateCheatMenu()
            if n > 0 then log("ZH: %d labels translated", n) end
        end, delay)
    end
end

--##############################################################################
-- toggles
--##############################################################################

local function toggle(name, onEnable, onDisable)
    state[name] = not state[name]
    if state[name] then
        if onEnable then onEnable() end
        log("%s: ON", name)
    else
        if onDisable then onDisable() end
        log("%s: OFF", name)
    end
    return state[name]
end

local function tick()
    if state.god then applyGodMode() end
    if state.ammo then refillAmmo() end
    if state.movement then applyMovement() end
    if state.speed then applySpeed() end
    if state.gravity then applyGravity() end
end

--##############################################################################
-- key binds
--##############################################################################

local function runInGameThread(fn)
    return function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then log("error: %s", tostring(err)) end
        end)
    end
end

local keyBinds = {
    { name = "F1",  vk = 0x70, action = runInGameThread(function() toggle("god", applyGodMode, clearGodMode) end) },
    { name = "F2",  vk = 0x71, action = runInGameThread(function()
        toggle("ammo", nil, nil)
        if state.ammo then refillAmmo() end
    end) },
    { name = "F3",  vk = 0x72, action = runInGameThread(function() toggle("movement", applyMovement, nil) end) },
    { name = "F4",  vk = 0x73, action = runInGameThread(function() toggle("speed", applySpeed, clearSpeed) end) },
    { name = "F5",  vk = 0x74, action = runInGameThread(function() toggle("gravity", applyGravity, clearGravity) end) },
    { name = "F6",  vk = 0x75, action = runInGameThread(function() addGold(CONFIG.goldAmount) end) },
    { name = "F7",  vk = 0x76, action = runInGameThread(function() addSouls(CONFIG.soulAmount) end) },
    { name = "F8",  vk = 0x77, action = runInGameThread(function() addUranium(CONFIG.uraniumAmount) end) },
    { name = "F9",  vk = 0x78, action = runInGameThread(fullHeal) },
    { name = "F10", vk = 0x79, action = runInGameThread(killEnemies) },
    { name = "F11", vk = 0x7A, action = runInGameThread(revealMap) },
    { name = "F12", vk = 0x7B, action = runInGameThread(toggleFreecam) },
    { name = "Insert", vk = 0x2D, action = runInGameThread(fullHeal) },
    { name = "Delete", vk = 0x2E, action = runInGameThread(refillAmmo) },
}

local function registerBinds()
    local bound = 0
    for _, bind in ipairs(keyBinds) do
        local keyArg = bind.vk
        if type(Key) == "table" and Key[bind.name] ~= nil then
            keyArg = Key[bind.name]
        end
        if pcall(RegisterKeyBind, keyArg, bind.action) then
            bound = bound + 1
        else
            log("could not bind %s", bind.name)
        end
    end
    log("hotkeys bound: %d/%d", bound, #keyBinds)
end

--##############################################################################
-- console
--##############################################################################

local HELP = [[
ffw commands:
  god | ammo | jump | speed | gravity   toggle a cheat
  freecam                               toggle the game's freecam pawn (same as F12)
  menu                                  open the game's own debug menu (try after freecam)
  gold [n] | souls [n] | uranium [n]     add currency (default 10000)
  heal | kill | reveal                  one-shot actions
  fix                                   hand keyboard control back to the character
  calls on|off                          allow/forbid blueprint function calls
  zh                                    re-run the menu translation
  status                                show what the mod can see
  diag                                  detailed object report

Also callable as Lua (UE4SS Lua console): ffw("gold", 99999), ffw("menu")
]]

local function status()
    local pawn = getPawn()
    local ps = getPlayerState(pawn)
    local gs = getGameState()
    log("pawn=%s playerState=%s gameState=%s",
        pawn and "ok" or "nil", ps and "ok" or "nil", gs and "ok" or "nil")
    if ps then
        log("heal=%s/%s invincible=%s",
            tostring(getNumber(ps, "playerHeal")),
            tostring(getNumber(ps, "playerMaxHeal")),
            tostring(getBool(ps, "invincible")))
    end
    if gs then
        log("gold=%s souls=%s uranium=%s",
            tostring(getNumber(gs, "pickedUpGolds")),
            tostring(getNumber(gs, "pickedUpSouls")),
            tostring(getNumber(gs, "pickedUpUranium")))
    end
    log("toggles: god=%s ammo=%s jump=%s speed=%s gravity=%s",
        tostring(state.god), tostring(state.ammo), tostring(state.movement),
        tostring(state.speed), tostring(state.gravity))
end

local function diag()
    local pawn = getPawn()
    local ps = getPlayerState(pawn)
    local gs = getGameState()
    local shield = getShield(ps)
    log("pawn       : %s", nameOf(pawn) or "nil")
    log("playerState: %s", nameOf(ps) or "nil")
    log("gameState  : %s", nameOf(gs) or "nil")
    log("shield     : %s", nameOf(shield) or "nil")
    log("blueprint calls enabled: %s", tostring(ALLOW_BLUEPRINT_CALLS))
    if ps then
        log("heal=%s max=%s invincible=%s",
            tostring(getNumber(ps, "playerHeal")), tostring(getNumber(ps, "playerMaxHeal")),
            tostring(getBool(ps, "invincible")))
    end
end

local function handleCommand(args)
    local action = (args[1] or "help"):lower()
    local amount = tonumber(args[2])

    if action == "god" then toggle("god", applyGodMode, clearGodMode)
    elseif action == "ammo" then
        toggle("ammo", nil, nil)
        if state.ammo then refillAmmo() end
    elseif action == "jump" then toggle("movement", applyMovement, nil)
    elseif action == "speed" then toggle("speed", applySpeed, clearSpeed)
    elseif action == "gravity" then toggle("gravity", applyGravity, clearGravity)
    elseif action == "gold" then addGold(amount)
    elseif action == "souls" then addSouls(amount)
    elseif action == "uranium" then addUranium(amount)
    elseif action == "heal" then fullHeal()
    elseif action == "kill" then killEnemies()
    elseif action == "reveal" then revealMap()
    elseif action == "freecam" then toggleFreecam()
    elseif action == "menu" then toggleCheatMenu()
    elseif action == "fix" then recoverControl()
    elseif action == "zh" then
        local n = translateCheatMenu()
        log("ZH: %d labels translated this pass", n)
    elseif action == "calls" then
        ALLOW_BLUEPRINT_CALLS = (args[2] or ""):lower() ~= "off"
        log("blueprint function calls: %s", ALLOW_BLUEPRINT_CALLS and "enabled" or "disabled")
        log("(disabled means: property writes only - no ammo refill, no enemy clearing)")
    elseif action == "status" then status()
    elseif action == "diag" then diag()
    else log("%s", HELP) end
end

--##############################################################################
-- start
--##############################################################################

registerBinds()

--- Console plumbing.
--- Two things used to break this:
---   * registration was wrapped in pcall and its result ignored, so a failure was silent;
---   * only RegisterConsoleCommandHandler was used, which fires in the
---     UGameViewportClient context - commands typed into UE4SS's own ImGui console do
---     not go through that path, so "ffw ..." looked dead there.
--- Now the global handler is preferred (all contexts), the specific one is the
--- fallback, both are reported, and a short debounce prevents double execution
--- when a single command happens to hit both paths.
local lastCmd, lastCmdAt = nil, 0.0

local function consoleHandler(cmd, params, ar)
    local key = tostring(cmd)
    local now = (os.clock and os.clock()) or 0.0
    if lastCmd == key and (now - lastCmdAt) < 0.3 then
        return true
    end
    lastCmd, lastCmdAt = key, now

    lastOut = ar
    log("command: %s", key)
    local ok, err = pcall(handleCommand, params or {})
    if not ok then log("command error: %s", tostring(err)) end
    lastOut = nil
    return true
end

local consoleAttempts = 0

local function ensureConsole()
    consoleAttempts = consoleAttempts + 1

    local hasGlobal = type(RegisterConsoleCommandGlobalHandler) == "function"
    local hasLocal = type(RegisterConsoleCommandHandler) == "function"
    local which, ok = "none", false

    -- global first: it covers the viewport console *and* UE4SS's own console
    if hasGlobal then
        ok = pcall(RegisterConsoleCommandGlobalHandler, "ffw", consoleHandler)
        if ok then which = "global" end
    end
    if not ok and hasLocal then
        ok = pcall(RegisterConsoleCommandHandler, "ffw", consoleHandler)
        if ok then which = "viewport" end
    end

    log("console 'ffw' registration (attempt %d): %s (global api=%s, viewport api=%s)",
        consoleAttempts, ok and which or "FAILED", tostring(hasGlobal), tostring(hasLocal))

    if not ok and consoleAttempts < 6 then
        ExecuteWithDelay(2000, function()
            ExecuteInGameThread(ensureConsole)
        end)
    end
end

ensureConsole()

-- Translate the widget template early; this also proves the text setter works and
-- reports the count in the log before any menu is opened.
ExecuteWithDelay(12000, function()
    ExecuteInGameThread(function()
        local ok, n = pcall(translateTemplate)
        if ok then
            log("ZH: template labels translated: %d", n or 0)
        else
            log("ZH: template translation failed: %s", tostring(n))
        end
    end)
end)

--- Second entry point, for UE4SS's own console which runs Lua rather than game
--- console commands:   ffw("gold", 99999)   /   ffw("diag")
_G.ffw = function(...)
    local args = table.pack(...)
    local ok, err = pcall(handleCommand, args)
    if not ok then log("error: %s", tostring(err)) end
end

local function scheduleTick()
    ExecuteWithDelay(CONFIG.tickMs, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(tick)
            if not ok then log("tick error: %s", tostring(err)) end
        end)
        scheduleTick()
    end)
end

scheduleTick()

log("loaded - F1 god mode, F6-F8 currency, F10 clear enemies, 'ffw help' for the rest")
