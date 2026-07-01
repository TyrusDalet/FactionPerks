--[[
TG:
        FPerks_TG1_Passive               = Ability, +3 Agility, +3 Speed, +5 Sneak, +5 Security
        FPerks_TG2_Passive               = Ability, +5 Agility, +5 Speed, +10 Sneak, +10 Security
        FPerks_TG3_Passive               = Ability, +10 Agility, +10 Speed, +18 Sneak, +18 Security
        FPerks_TG4_Passive               = Ability, +15 Agility, +15 Speed, +25 Sneak, +25 Security
        FPerks_TG3_Cham                  - Ability, 25 Chameleon
        FPerks_TG4_Cham                  - Ability, 50 Chameleon
]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local storage    = require('openmw.storage')
local core       = require('openmw.core')
local ui         = require('openmw.ui')


-- ============================================================
--  STORAGE
-- ============================================================
local perkStore = storage.playerSection("FactionPerks")

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R      = interfaces.ErnPerkFramework.requirements
local utils  = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local safeAddSpell  = utils.safeAddSpell
local safeRemoveSpell = utils.safeRemoveSpell
local GUILD        = utils.FACTION_GROUPS.thievesGuild

local hasChameleon25 = false
local hasChameleon50 = false

-- Create a table with all the Faction spell effects in it
local perkTable = {
    [1] = { attributes = { agility=3,  speed=3  }, skills = { sneak=5,  security=5  } },
    [2] = { attributes = { agility=5,  speed=5  }, skills = { sneak=10, security=10 } },
    [3] = { attributes = { agility=10, speed=10 },
            skills = { sneak=18, security=18 },
            flags   = { hasChameleon25 = true }, },
    [4] = { attributes = { agility=15, speed=15 },
            skills = { sneak=25, security=25 }, 
            flags   = { hasChameleon50 = true },},
}

local appliedStats = { attributes = {}, skills = {} }

-- Flag Handler - allows us to control the state of the chameleon flags from multiple locations
local flagHandlers = {
    hasChameleon25 = function(v) hasChameleon25 = v end,
    hasChameleon50 = function(v) hasChameleon50 = v end,
}

local setRank = utils.makeSetRank(perkTable, flagHandlers, appliedStats)


-- Perk id prep
local tg1_id = ns .. "_tg_light_fingers"
local tg2_id = ns .. "_tg_shadow_step"
local tg3_id = ns .. "_tg_fence_network"
local tg4_id = ns .. "_tg_master_thief"


-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Thieves Guild Perks"

local function getTGRank()
    if R().hasPerk(tg4_id).check() then return 4 end
    if R().hasPerk(tg3_id).check() then return 3 end
    if R().hasPerk(tg2_id).check() then return 2 end
    if R().hasPerk(tg1_id).check() then return 1 end
    return nil
end

local function reportAAM()
    if not interfaces.AAM then return end
    local rank = getTGRank() -- your faction's getXXRank() function
    if not rank then
        interfaces.AAM.reportExternalModifiers(FACTION_DISPLAY_NAME, nil)
        return
    end
    local rankData = perkTable[rank]
    local report = {}
    for id, val in pairs(rankData.attributes or {}) do report[id] = val end
    for id, val in pairs(rankData.skills     or {}) do report[id] = val end
    if next(report) then
        interfaces.AAM.reportExternalModifiers(FACTION_DISPLAY_NAME, report)
    else
        interfaces.AAM.reportExternalModifiers(FACTION_DISPLAY_NAME, nil)
    end
end

-- ============================================================
--  CHAMELEON (Thieves Guild P3 / P4)
-- ============================================================
local chameleonActive = false

local function chameleonMag()
    local m = 0
    if hasChameleon25 then m = m + 25 end
    if hasChameleon50 then m = m + 50 end
    return m
end
local function applyChameleon()
    if not chameleonActive then
        local m = chameleonMag()
        if m >= 25 then 
            safeAddSpell("FPerks_TG3_Cham") 
            chameleonActive = true

            if m == 50 then 
                safeAddSpell("FPerks_TG4_Cham") 
            end
        end
    end
end
local function removeChameleon()
    if chameleonActive then
        safeRemoveSpell("FPerks_TG3_Cham")
        safeRemoveSpell("FPerks_TG4_Cham")
        chameleonActive = false
    end
end

-- ============================================================
--  onUpdate
-- ============================================================

local function onUpdate()
    -- Chameleon sneak tracking
    if hasChameleon25 or hasChameleon50 then
        if self.controls.sneak == true and not chameleonActive then
            applyChameleon()
        elseif self.controls.sneak ~= true and chameleonActive then
            -- Fixed: was `not self.controls.sneak == true` which parses as
            -- `(not self.controls.sneak) == true` - accidentally correct but
            -- misleading. Rewritten as `self.controls.sneak ~= true` for clarity.
            removeChameleon()
        end
    elseif chameleonActive then
        removeChameleon()
    end
end

-- ============================================================
--  THIEVES GUILD
--  Primary attributes: Agility, Speed
--  Scaling: Sneak, Security
--  Special: passive Chameleon 25% (Fence Network) - 50% total
--           (Master Thief) while sneaking
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = tg1_id,
    localizedName = "Light Fingers",
    category = {"Imperial Factions", "Thieves Guild", 1},
    localizedFlavour = "Years of petty theft have given you an instinct for opportunity. "
        .. "Your hands are quick and your presence quiet.",
    localizedDescription = "Grants the following stats: (+3 Agility, +3 Speed, +5 Sneak, +5 Security)",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\acrobat",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("thievesGuild",0),
        R().minimumLevel(1)
    },
    onAdd = function()
        setRank(1)
        reportAAM()
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tg2_id,
    localizedName = "Shadow Step",
    category = {"Imperial Factions", "Thieves Guild", 2},
    localizedFlavour = "You have learned to move between pools of darkness with uncanny ease. "
        .. "Guards look straight through you.",
    localizedDescription = "Grants the following stats: (+5 Agility, +5 Speed, "
        .. "+10 Sneak, +10 Security)",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\acrobat",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R().hasPerk(tg1_id),
        FactionGroupRank("thievesGuild",3),
        R().minimumAttributeLevel('agility', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        reportAAM()
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tg3_id,
    localizedName = "Fence Network",
    category = {"Imperial Factions", "Thieves Guild", 3},
    localizedFlavour = "You have cultivated contacts willing to move stolen goods with no questions asked. "
        .. "When you crouch, shadow swallows you whole.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+10 Agility, +10 Speed, "
        .. "+18 Sneak, +18 Security)\f"
        .. "Effect 2: \n 25% Chameleon while sneaking.",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\acrobat",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R().hasPerk(tg2_id),
        FactionGroupRank("thievesGuild",6),
        R().minimumAttributeLevel('agility', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
        reportAAM()
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tg4_id,
    localizedName = "Master Thief",
    category = {"Imperial Factions", "Thieves Guild", 4},
    localizedFlavour = "There is no lock you cannot pick, no pocket you cannot cut. "
        .. "Crouch, and you vanish almost entirely from sight.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Agility, +15 Speed, "
        .. "+25 Sneak, +25 Security)\f"
        .. "Effect 2: \n 25% additional Chameleon while sneaking (50% total with Fence Network).",
    hidden = perkHidden(GUILD, 9, 15),
    art = "textures\\levelup\\acrobat",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        R().hasPerk(tg3_id),
        FactionGroupRank("thievesGuild",9),
        R().minimumAttributeLevel('agility', 75),
        R().minimumLevel(15),
    },
   onAdd = function()
        setRank(4)
        reportAAM()
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================
local function onSave()
    return {
        hasChameleon25 = hasChameleon25,
        hasChameleon50 = hasChameleon50,
        appliedStats = appliedStats
    }
end

local function onLoad(data)
    data = data or {}
    hasChameleon25 = data.hasChameleon25 or false
    hasChameleon50 = data.hasChameleon50 or false
    local saved = data.appliedStats or { attributes = {}, skills = {} }
    for id, val in pairs(saved.attributes or {}) do
        if val ~= 0 then
            types.Actor.stats.attributes[id](self).modifier =
                types.Actor.stats.attributes[id](self).modifier - val
        end
    end
    for id, val in pairs(saved.skills or {}) do
        if val ~= 0 then
            types.NPC.stats.skills[id](self).modifier =
                types.NPC.stats.skills[id](self).modifier - val
        end
    end
    -- Clear so setRank re-populates cleanly on re-fire
    appliedStats.attributes = {}
    appliedStats.skills     = {}
end


return {
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
        onUpdate = onUpdate,
    }
}
