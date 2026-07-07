--[[
    TT:
        FPerks_TT1_Passive          - +3 Intelligence, +3 Willpower,
                                      +5 Restoration, +5 Mysticism
        FPerks_TT2_Passive          - +5 Intelligence, +5 Willpower,
                                      +10 Restoration, +10 Mysticism
        FPerks_TT3_Passive          - +10 Intelligence, +10 Willpower,
                                      +18 Restoration, +18 Mysticism
        FPerks_TT4_Passive          - +15 Intelligence, +15 Willpower,
                                      +25 Restoration, +25 Mysticism

    Non-table spells (granted once, not removed on rank-up):
        "almsivi intervention"      Vanilla spell (P1)
        FPerks_TT2_Cure_All         Power (P2)
        FPerks_TT4_Summon_Army      Power (P4)

    Honoured Ancestors (P3+):
        Ancestor Ghosts, Bonelords, and Bonewalkers will not
        attack the player. Non-summoned instances are calmed
        when they become active in the player's cell.
        Handled via creature.lua ping + player response pattern.
        Reversed cleanly if the perk is lost.
]]

local ns          = require("scripts.FactionPerks.namespace")
local utils       = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local safeAddSpell  = utils.safeAddSpell
local safeRemoveSpell = utils.safeRemoveSpell
local GUILD        = utils.FACTION_GROUPS.temple
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local core        = require('openmw.core')
local nearby      = require('openmw.nearby')

local R = utils.requirements

local perkTable = {
    [1] = { attributes = { intelligence=3,  willpower=3  }, skills = { restoration=5,  mysticism=5 } },
    [2] = { attributes = { intelligence=5,  willpower=5  }, skills = { restoration=10, mysticism=10 } },
    [3] = { attributes = { intelligence=10, willpower=10 }, skills = { restoration=18, mysticism=18 } },
    [4] = { attributes = { intelligence=15, willpower=15 }, skills = { restoration=25, mysticism=25 } },
}

local appliedStats = { attributes = {}, skills = {} }

local tt1_id = ns .. "_tt_ordinate_aspirant"
local tt2_id = ns .. "_tt_pilgrim_soul"
local tt3_id = ns .. "_tt_voice_of_reclamation"
local tt4_id = ns .. "_tt_hand_of_almsivi"

local setRank = utils.makeSetRank(perkTable, nil, appliedStats)

-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Tribunal Temple Perks"



local function getTTRank()
    if R().hasPerk(tt4_id).check() then return 4 end
    if R().hasPerk(tt3_id).check() then return 3 end
    if R().hasPerk(tt2_id).check() then return 2 end
    if R().hasPerk(tt1_id).check() then return 1
    else return 0
    end
end

local function reportAAM()
    if not interfaces.AAM then return end
    local rank = getTTRank() -- your faction's getXXRank() function
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

-- ============================================================
--  HONOURED ANCESTORS - Voice of Reclamation (P3+)
-- ============================================================

local hasTTHonouredAncestors = false

local HONOURED_ANCESTOR_IDS = {
    ["ancestor ghost"] = true,
    ["bonelord"]       = true,
    ["bonewalker"]     = true,
}

local function isHonouredAncestorActor(actor)
    if not types.Creature.objectIsInstance(actor) then return false end
    local id = (types.Creature.record(actor).id or ""):lower()
    for name, _ in pairs(HONOURED_ANCESTOR_IDS) do
        if id:find(name, 1, true) then return true end
    end
    return false
end

local function restoreNearbyAncestors()
    for _, actor in pairs(nearby.actors) do
        if isHonouredAncestorActor(actor) then
            actor:sendEvent(ns .. "_TT_RestoreAncestor", {})
        end
    end
end

local function ancestorSpawned(data)
    if not hasTTHonouredAncestors then return end
    if not data.creature or not data.creature:isValid() then return end
    data.creature:sendEvent(ns .. "_TT_CalmAncestor", {})
end

-- ============================================================
--  TRIBUNAL TEMPLE PERKS
--  Primary attributes: Intelligence, Willpower
--  Scaling: Restoration, Mysticism
--  Special: Almsivi Intervention (P1), Cure All power (P2),
--           Honoured Ancestors (P3+), Summon Army power (P4)
-- ============================================================


interfaces.ErnPerkFramework.registerPerk({
    id = tt1_id,
    localizedName = "Ordinate Aspirant",
    category = {"Dunmeri Factions", "Tribunal Temple", 1},
    localizedFlavour = "You have taken up the Temple's creed and begun study of its mysteries. "
        .. "ALMSIVI turns aside blows and afflictions that threaten their faithful.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+3 Intelligence, +3 Willpower, "
        .. "+5 Restoration, +5 Mysticism)\f"
        .. "Effect 2: \n Grants Almsivi Intervention.",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("temple",0),
        R().minimumLevel(1)
    },
    onAdd = function()
        setRank(1)
        reportAAM()
        safeAddSpell("almsivi intervention")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("almsivi intervention")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tt2_id,
    localizedName = "Pilgrim Soul",
    category = {"Dunmeri Factions", "Tribunal Temple", 2},
    localizedFlavour = "You have walked the Pilgrimages of the Seven Graces. "
        .. "Once each day you may call upon ALMSIVI to cleanse disease, poison, and blight.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+5 Intelligence, +5 Willpower, "
        .. "+10 Restoration, +10 Mysticism)\f"
        .. "Effect 2: \n Grants Touch of ALMSIVI (1/day): Cure Disease, Cure Blight, "
        .. "and Cure Poison on Touch.",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R().hasPerk(tt1_id),
        FactionGroupRank("temple",3),
        R().minimumAttributeLevel('willpower', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        reportAAM()
        safeAddSpell("FPerks_TT2_Cure_All")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("FPerks_TT2_Cure_All")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tt3_id,
    localizedName = "Voice of Reclamation",
    category = {"Dunmeri Factions", "Tribunal Temple", 3},
    localizedFlavour = "The Temple's holy authority now speaks through you. "
        .. "Ancestor Ghosts, Bonelords, and Bonewalkers recognise you as a servant of ALMSIVI.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+10 Intelligence, +10 Willpower, "
        .. "+18 Restoration, +18 Mysticism)\f"
        .. "Effect 2: \n Honoured Ancestors: Non-summoned Ancestor Ghosts, Bonelords, and "
        .. "Bonewalkers will not attack you.",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R().hasPerk(tt2_id),
        FactionGroupRank("temple",6),
        R().minimumAttributeLevel('willpower', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
        reportAAM()
        hasTTHonouredAncestors = true
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        hasTTHonouredAncestors = false
        restoreNearbyAncestors()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = tt4_id,
    localizedName = "Hand of ALMSIVI",
    category = {"Dunmeri Factions", "Tribunal Temple", 4},
    localizedFlavour = "You are an instrument of Vivec, Almalexia, and Sotha Sil. "
        .. "Once each day you may call upon the honoured dead to fight at your side.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Intelligence, +15 Willpower, "
        .. "+25 Restoration, +25 Mysticism)\f"
        .. "Effect 2: \n Grants Call Honoured Ancestors (1/day): Summon 2 Greater Bonewalkers "
        .. "and 2 Bonelords for 60s.",
    hidden = perkHidden(GUILD, 9, 15),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        R().hasPerk(tt3_id),
        FactionGroupRank("temple",9),
        R().minimumAttributeLevel('willpower', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        reportAAM()
        safeAddSpell("FPerks_TT4_Summon_Army")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("FPerks_TT4_Summon_Army")
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
    eventHandlers = {
        [ns .. "_TT_AncestorSpawned"] = ancestorSpawned,
    },
        engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    }

}
