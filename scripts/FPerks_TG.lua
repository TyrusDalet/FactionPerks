local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local ui         = require('openmw.ui')
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local nearby     = require('openmw.nearby')
local storage    = require('openmw.storage')

local perkStore = storage.playerSection("FactionPerks")

local FX = {}
local function loadFX()
    local function fx(id)
        local e = core.magic.effects.records[id]
        if not e then print("WARNING Faction Perks: effect not found — " .. id) end
        return e
    end
    FX.chameleon       = fx("chameleon")
end
loadFX()

-- ============================================================
--  CORE HELPERS
-- ============================================================

local function modEffect(effect, mag)
    if effect then
        types.Actor.stats(self).magicEffects:modify(effect, mag)
    end
end

local function modStat(statType, name, amount)
    local stats = types.Actor.stats(self)
    if statType == "skill" then
        local s = stats.skills[name]
        if s then s.modifier = s.modifier + amount end
    elseif statType == "attribute" then
        local a = stats.attributes[name]
        if a then a.modifier = a.modifier + amount end
    end
end

local function addSpell(id)
    local rec = core.magic.spells.records[id]
    if rec then
        types.Actor.spells(self):add(id)
    else
        print("WARNING Faction Perks: spell record not found — " .. id)
    end
end

local function removeSpell(id)
    types.Actor.spells(self):remove(id)
end

local function msg(text)
    ui.showMessage(text, {})
    print(text)
end

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements



-- ============================================================
--  CHAMELEON (Thieves Guild P3 / P4)
-- ============================================================
local chameleonActive = false
local hasChameleon25  = false
local hasChameleon50  = false

local function chameleonMag()
    local m = 0
    if hasChameleon25 then m = m + 25 end
    if hasChameleon50 then m = m + 25 end
    return m
end
local function applyChameleon()
    if not chameleonActive then
        local m = chameleonMag()
        if m > 0 then modEffect(FX.chameleon, m); chameleonActive = true end
    end
end
local function removeChameleon()
    if chameleonActive then
        modEffect(FX.chameleon, -chameleonMag()); chameleonActive = false
    end
end

-- ============================================================
--  THIEVES GUILD
--  Primary attribute: Agility
--  Scaling: Sneak, Security, Acrobatics, Mercantile
--  Special: passive Chameleon 25% (Fence Network) → 50% total
--           (Master Thief) while sneaking
-- ============================================================

local tg1_id = ns .. "_tg_light_fingers"
interfaces.ErnPerkFramework.registerPerk({
    id = tg1_id,
    localizedName = "Light Fingers",
    localizedDescription = "Years of petty theft have given you an instinct for opportunity. "
        .. "Your hands are quick and your presence quiet. "
        .. "(+5 Agility, +10 Sneak, +10 Security)",
    art = "textures\\levelup\\acrobat", cost = 1,
    requirements = {
        R().minimumFactionRank('thieves guild', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        modStat("attribute","agility", 5)
        modStat("skill","sneak",      10)
        modStat("skill","security",   10)
        msg("Light Fingers granted.")
    end,
    onRemove = function()
        modStat("attribute","agility", -5)
        modStat("skill","sneak",      -10)
        modStat("skill","security",   -10)
        msg("Light Fingers lost.")
    end,
})

local tg2_id = ns .. "_tg_shadow_step"
interfaces.ErnPerkFramework.registerPerk({
    id = tg2_id,
    localizedName = "Shadow Step",
    localizedDescription = "You have learned to move between pools of darkness with uncanny ease. "
        .. "Guards look straight through you. "
        .. "(+15 Agility, +25 Sneak, +25 Acrobatics)",
    art = "textures\\levelup\\acrobat", cost = 2,
    requirements = {
        R().hasPerk(tg1_id),
        R().minimumFactionRank('thieves guild', 3),
        R().minimumAttributeLevel('agility', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        modStat("attribute","agility",  15)
        modStat("skill","sneak",        25)
        modStat("skill","acrobatics",   25)
        msg("Shadow Step granted.")
    end,
    onRemove = function()
        modStat("attribute","agility",  -15)
        modStat("skill","sneak",        -25)
        modStat("skill","acrobatics",   -25)
        msg("Shadow Step lost.")
    end,
})

local tg3_id = ns .. "_tg_fence_network"
interfaces.ErnPerkFramework.registerPerk({
    id = tg3_id,
    localizedName = "Fence Network",
    localizedDescription = "You have cultivated contacts willing to move stolen goods with no "
        .. "questions asked. When you crouch, shadow swallows you whole. "
        .. "Requires Shadow Step. "
        .. "(+20 Agility, +50 Sneak, +50 Mercantile, 25% Chameleon while sneaking)",
    art = "textures\\levelup\\acrobat", cost = 3,
    requirements = {
        R().hasPerk(tg2_id),
        R().minimumFactionRank('thieves guild', 6),
        R().minimumAttributeLevel('agility', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        modStat("attribute","agility",  20)
        modStat("skill","sneak",        50)
        modStat("skill","mercantile",   50)
        hasChameleon25 = true
        if types.Actor.stance(self) == types.Actor.STANCE_SNEAK then applyChameleon() end
        msg("Fence Network granted.")
    end,
    onRemove = function()
        modStat("attribute","agility",  -20)
        modStat("skill","sneak",        -50)
        modStat("skill","mercantile",   -50)
        removeChameleon(); hasChameleon25 = false
        if hasChameleon50 and types.Actor.stance(self) == types.Actor.STANCE_SNEAK then
            applyChameleon()
        end
        msg("Fence Network lost.")
    end,
})

local tg4_id = ns .. "_tg_master_thief"
interfaces.ErnPerkFramework.registerPerk({
    id = tg4_id,
    localizedName = "Master Thief",
    localizedDescription = "There is no lock you cannot pick, no pocket you cannot cut. "
        .. "Crouch, and you vanish almost entirely from sight. "
        .. "Requires Fence Network. "
        .. "(+25 Luck, +75 Security, 50% Chameleon while sneaking)",
    art = "textures\\levelup\\acrobat", cost = 4,
    requirements = {
        R().hasPerk(tg3_id),
        R().minimumFactionRank('thieves guild', 9),
        R().minimumAttributeLevel('agility', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","luck",  25)
        modStat("skill","security",  75)
        removeChameleon(); hasChameleon50 = true
        if types.Actor.stance(self) == types.Actor.STANCE_SNEAK then applyChameleon() end
        msg("Master Thief granted.")
    end,
    onRemove = function()
        modStat("attribute","luck",  -25)
        modStat("skill","security",  -75)
        removeChameleon(); hasChameleon50 = false
        if hasChameleon25 and types.Actor.stance(self) == types.Actor.STANCE_SNEAK then
            applyChameleon()
        end
        msg("Master Thief lost.")
    end,
})