--[[
 MT:
        FPerks_MT1_Passive               - +3 Speed, +3 Agility, +5 Sneak, +5 Acrobatics
        FPerks_MT2_Passive               - +5 Speed, +5 Agility, +10 Sneak, +10 Acrobatics
        FPerks_MT3_Passive               - +10 Speed, +10 Agility, +18 Sneak, +18 Acrobatics
        FPerks_MT4_Passive               - +15 Speed, +15 Agility, +25 Sneak, +25 Acrobatics
        FPerks_MT2_Frenzy                - Spell, Frenzy, free, unlimited
        FPerks_MT4_Invisibility          - Spell, Invisibility, free, unlimited
        FPerks_MT4_Lifesteal             - Spell Effect, Absorb Life 25pts 5s
]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local ui         = require('openmw.ui')
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local nearby     = require('openmw.nearby')
local storage    = require('openmw.storage')
local async      = require('openmw.async')
local input      = require('openmw.input')

require('scripts.FactionPerks.shared')


local perkStore = storage.playerSection("FactionPerks")
local utils  = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local safeAddSpell  = utils.safeAddSpell
local safeRemoveSpell = utils.safeRemoveSpell
local GUILD        = utils.FACTION_GROUPS.moragTong
local HasMT4 = false

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = utils.requirements

-- Create a table with all the Faction spell effects in it
local perkTable = {
    [1] = { attributes = { speed=3,  agility=3  }, skills = { sneak=5,  acrobatics=5  } },
    [2] = { attributes = { speed=5,  agility=5  }, skills = { sneak=10, acrobatics=10 } },
    [3] = { attributes = { speed=10, agility=10 }, skills = { sneak=18, acrobatics=18 } },
    [4] = {
        attributes = { speed=15, agility=15 },
        skills = { sneak=25, acrobatics=25 },
        flags   = { HasMT4 = true }  }
}

-- Flag Handler - allows us to control the state of the HasMT4 flag from multiple locations
local flagHandlers = {
    HasMT4 = function(v) HasMT4 = v end,
}

-- Perk id prep
local mt1_id = ns .. "_mt_writ_bearer"
local mt2_id = ns .. "_mt_blade_discipline"
local mt3_id = ns .. "_mt_calm_before"
local mt4_id = ns .. "_mt_honoured_executioner"

local appliedStats = { attributes = {}, skills = {} }
local setRank = utils.makeSetRank(perkTable, flagHandlers, appliedStats)


-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Morag Tong Perks"

local function getMTRank()
    if R().hasPerk(mt4_id).check() then return 4 end
    if R().hasPerk(mt3_id).check() then return 3 end
    if R().hasPerk(mt2_id).check() then return 2 end
    if R().hasPerk(mt1_id).check() then return 1 
    else return 0
    end
end

local function reportAAM()
    if not interfaces.AAM then return end
    local rank = getMTRank() -- your faction's getXXRank() function
    if rank == 0 then
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

-- Morag Tong Life Steal sneak attacks

input.registerActionHandler(input.actions.Sneak.key, async:callback(function() --Whenever you're crouched
    if HasMT4 == true then --If the player has MT perk 4
        for _, actor in pairs(nearby.actors) do -- For each nearby actor
        actor:sendEvent("playerSneaking", self.controls.sneak) --Send them an event handler saying that the player is sneaking -- IGNORE THE LLS THIS WORKS
        end
    end
end))

-- ============================================================
--  MORAG TONG
--  Primary attributes: Speed, Agility
--  Scaling: Sneak, Acrobatics
--  Special: Frenzy power (Blade Discipline),
--           Invisibility power (Honoured Executioner),
--           Lifesteal on sneak attack (Honoured Executioner)
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = mt1_id,
    localizedName = "Writ Bearer",
    category = {"Dunmeri Factions", "Morag Tong", 1},
    localizedFlavour = "You carry the legal sanction of the Morag Tong. "
        .. "Your kills are honoured executions, not murders.",
    localizedDescription = "Grants the following stats: (+3 Speed, +3 Agility, +5 Sneak, +5 Acrobatics)",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\knight",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("moragTong",0),
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
    id = mt2_id,
    localizedName = "Blade Discipline",
    category = {"Dunmeri Factions", "Morag Tong", 2},
    localizedFlavour = "The Tong teaches economy of motion. Your strikes are precise and swift. "
        .. "You have learned to channel pure battle-fury at will.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+5 Speed, +5 Agility, "
        .. "+10 Sneak, +10 Acrobatics)\f"
        .. "Effect 2: \n Grants Mephala's Touch: Frenzy Humanoid 50pts for 30s.",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\knight",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R().hasPerk(mt1_id),
        FactionGroupRank("moragTong",3),
        R().minimumAttributeLevel('speed', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        reportAAM()
        safeAddSpell("FPerks_MT2_Frenzy");
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("FPerks_MT2_Frenzy");
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = mt3_id,
    localizedName = "Calm Before",
    category = {"Dunmeri Factions", "Morag Tong", 3},
    localizedFlavour = "You have learned the art of stillness. "
        .. "A Tong assassin who cannot wait cannot succeed.",
    localizedDescription = "Grants the following stats: (+10 Speed, +10 Agility, "
        .. "+18 Sneak, +18 Acrobatics)",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\knight",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R().hasPerk(mt2_id),
        FactionGroupRank("moragTong",6),
        R().minimumAttributeLevel('speed', 50),
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
    id = mt4_id,
    localizedName = "Honoured Executioner",
    category = {"Dunmeri Factions", "Morag Tong", 4},
    localizedFlavour = "The Grand Master himself has commended your work. "
        .. "The shadows open for you whenever you call upon them.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Speed, +15 Agility, "
        .. "+25 Sneak, +25 Acrobatics)\f"
        .. "Effect 2: \n Grants Mephala's Shroud: Invisibility for 60s.\f"
        .. "Effect 3: \n Weapon attacks whilst Sneaking apply a 25pt for 5s Absorb Health effect.",
    hidden = perkHidden(GUILD, 9, 15),
    art = "textures\\levelup\\knight",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        R().hasPerk(mt3_id),
        FactionGroupRank("moragTong",9),
        R().minimumAttributeLevel('speed', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        reportAAM()
        safeAddSpell("FPerks_MT4_Invisibility");
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("FPerks_MT4_Invisibility");
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================

local function onSave()
    return { appliedStats = appliedStats }
end

local function onLoad(data)
    data = data or {}
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
    }

}
