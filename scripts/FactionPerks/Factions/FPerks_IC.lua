--[[
    IC:
        FPerks_IC1_Passive          - +3 Willpower, +3 Personality, +5 Speechcraft, +5 Restoration
        FPerks_IC2_Passive          - +5 Willpower, +5 Personality, +10 Speechcraft, +10 Restoration
        FPerks_IC3_Passive          - +10 Willpower, +10 Personality, +18 Speechcraft, +18 Restoration
        FPerks_IC4_Passive          - +15 Willpower, +15 Personality, +25 Speechcraft, +25 Restoration

    Non-table spells (granted once, not removed on rank-up):
        "divine intervention"       Vanilla spell (P1)
        FPerks_IC4_AllAttributes    Power (P4)

    Divine Smite (P3+):
        When the player strikes an undead, daedra, or vampire
        with a weapon, divine damage is dealt directly to the
        target bypassing all resistances.
        Damage = Imperial Cult faction rank x 10.
        Per-target cooldown: 10s at P3, 5s at P4.
        Detected via actor.lua hit handlers.
]]

local ns         = "FactionPerks"
local utils      = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local getFactionRank = utils.FactionGroupCurrentRank
local perkHidden  = utils.perkHidden
local safeAddSpell  = utils.safeAddSpell
local safeRemoveSpell = utils.safeRemoveSpell
local GUILD        = utils.FACTION_GROUPS.imperialCult
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local ui         = require('openmw.ui')
local ambient    = require('openmw.ambient')


local HasICSmite3 = false
local HasICSmite4 = false

local R = utils.requirements()

local perkTable = {
    [1] = { attributes = { willpower=3,  personality=3  }, skills = { speechcraft=5,  restoration=5  } },
    [2] = { attributes = { willpower=5,  personality=5  }, skills = { speechcraft=10, restoration=10 } },
    [3] = { attributes = { willpower=10, personality=10 }, skills = { speechcraft=18, restoration=18 }, flags = { hasICSmite3 = true } },
    [4] = { attributes = { willpower=15, personality=15 }, skills = { speechcraft=25, restoration=25 }, flags = { hasICSmite4 = true } },
}

-- Flag Handler - allows us to control the state of the HasMT4 flag from multiple locations
local flagHandlers = {
    hasICSmite3 = function(v) HasICSmite3 = v end,
    hasICSmite4 = function(v) HasICSmite4 = v end,
}

local appliedStats = { attributes = {}, skills = {} }

-- Perk id group
local ic1_id = ns .. "_ic_lay_worshipper"
local ic2_id = ns .. "_ic_charitable_hand"
local ic3_id = ns .. "_ic_divine_favour"
local ic4_id = ns .. "_ic_blessed_of_the_nine"

local setRank = utils.makeSetRank(perkTable, flagHandlers, appliedStats)




-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Imperial Cult Perks"

local function getICRank()
    return utils.highestOwnedPerkRank({
        [1] = ic1_id,
        [2] = ic2_id,
        [3] = ic3_id,
        [4] = ic4_id,
    })
end

local reportAAM = utils.makeAAMReporter(FACTION_DISPLAY_NAME, perkTable, getICRank)

-- ============================================================
--  SMITE FEEDBACK & SmiteLevelChecker
--  One message per Divine, chosen at random when the smite
--  fires. Each reflects that Divine's domain and the context
--  of striking the unholy. Sound uses the vanilla critical
--  attack cue for a satisfying confirmation.
--
-- Also responds to the CheckSmiteLevel event and sends it onto shared.lua
-- ============================================================

--- Resolves the player's current Imperial Cult Smite rank and forwards it to the target.
--- Actor-side code performs target classification first, then sends the attack/target
--- tuple here because only the player script knows which Imperial Cult perk flags are active.
--- @param attack table Tuple containing the attack table and target actor.
function CheckSmiteLevel(attack)
    utils.debug(3, "IC", "Reading Smite event")
    local smiteLevel = 0
    local attackInfo = attack[1]
    local target = attack[2]
    local package = {}
    local rank = 0
    if HasICSmite3 == true then
        smiteLevel = 3
    end
    if HasICSmite4 == true then
        smiteLevel = 4
    end
    utils.debug(3, "IC", "Smite level=" .. tostring(smiteLevel))

    rank = getFactionRank("imperialCult")

    package = {attackInfo, rank, smiteLevel}

    utils.debug(3, "IC", "Sending Smite information")
    target:sendEvent("DoICSmite", package)

end

local IC_SMITE_MESSAGES = {
    "Akatosh guides your hand.",
    "By Arkay's grace, the dead shall not stand.",
    "Dibella blesses your strike.",
    "Julianos illuminates the weakness of your foe.",
    "Kynareth's breath carries your blow true.",
    "Mara shields the living through your hand.",
    "Stendarr's mercy is not for the wicked.",
    "Talos strengthens the arm of his faithful.",
    "Zenithar rewards your devotion.",
}

--- Plays player-facing feedback after a target-side Smite successfully applies.
--- @param data table Smite payload containing the resolved damage amount.
local function onSmiteProc(data)
    ambient.playSound("critical attack")
    ui.showMessage(IC_SMITE_MESSAGES[math.random(#IC_SMITE_MESSAGES)])
end

-- ============================================================
--  IMPERIAL CULT PERKS
--  Primary attributes: Willpower, Personality
--  Scaling: Speechcraft, Restoration
--  Special: Divine Intervention (P1), Divine Smite (P3+),
--           Fortify All Attributes power (P4)
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = ic1_id,
    localizedName = "Lay Worshipper",
    category = {"FactionPerks", "Imperial Factions", "Imperial Cult", 1},
    localizedFlavour = "You have joined the Cult and attend its rites faithfully. "
        .. "The Nine Divines offer you modest but real protection.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+3 Willpower, +3 Personality, "
        .. "+5 Speechcraft, +5 Restoration)\f"
        .. "Effect 2: \n Grants Divine Intervention.",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("imperialCult", 0),
        R.minimumLevel(1)
    },
    onAdd = function()
        setRank(1)
        reportAAM()
        safeAddSpell("divine intervention")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("divine intervention")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = ic2_id,
    localizedName = "Charitable Hand",
    category = {"FactionPerks", "Imperial Factions", "Imperial Cult", 2},
    localizedFlavour = "You have distributed alms and tended to the sick in the name of the Divines. "
        .. "Your faith has strengthened your body as well as your spirit.",
    localizedDescription = "Grants the following stats: (+5 Willpower, +5 Personality, "
        .. "+10 Speechcraft, +10 Restoration)",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R.hasPerk(ic1_id),
        FactionGroupRank("imperialCult", 3),
        R.minimumAttributeLevel('willpower', 40),
        R.minimumLevel(5),
    },
    onAdd    = function()
        setRank(2)
        reportAAM()
        end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = ic3_id,
    localizedName = "Divine Favour",
    category = {"FactionPerks", "Imperial Factions", "Imperial Cult", 3},
    localizedFlavour = "The Divines have marked you as a servant of true worth. "
        .. "When you strike the unholy, divine power smites them through your hand.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+10 Willpower, +10 Personality, "
        .. "+18 Speechcraft, +18 Restoration)\f"
        .. "Effect 2: \n Divine Smite: Striking undead, daedra, or vampires with a weapon deals "
        .. "bonus divine damage equal to your Imperial Cult rank x10. 10s cooldown per target.",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R.hasPerk(ic2_id),
        FactionGroupRank("imperialCult", 6),
        R.minimumAttributeLevel('willpower', 50),
        R.minimumLevel(10),
    },
    onAdd    = function()
        setRank(3)
        reportAAM()
        end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = ic4_id,
    localizedName = "Blessed of the Nine",
    category = {"FactionPerks", "Imperial Factions", "Imperial Cult", 4},
    localizedFlavour = "The Nine Divines have extended their grace to you directly. "
        .. "Once each day you may call upon their full blessing.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Willpower, +15 Personality, "
        .. "+25 Speechcraft, +25 Restoration)\f"
        .. "Effect 2: \n Grants Blessing of the Nine (1/day): Fortify All Attributes +50 for 30s.\f"
        .. "Effect 3: \n Divine Smite cooldown reduced to 5s per target.",
    hidden = utils.leaderTrainingHidden("imperialCult", perkHidden(GUILD, 9, 15)),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        utils.leaderTrainingRequirement("imperialCult"),
        utils.leaderTrainingRankRequirement("imperialCult", 9),
        R.hasPerk(ic3_id),
        FactionGroupRank("imperialCult", 9),
        R.minimumAttributeLevel('willpower', 75),
        R.minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        reportAAM()
        safeAddSpell("FPerks_IC4_AllAttributes")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("FPerks_IC4_AllAttributes")
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
    utils.clearSavedAppliedStats(data.appliedStats, appliedStats)
end

return {
    eventHandlers = {
        FPerks_IC_CheckSmiteLevel = CheckSmiteLevel,
        FPerks_IC_SmiteProc = onSmiteProc,
        onSave = onSave,
        onLoad = onLoad,
    },
    engineHandlers = {
        onSave = onSave,
        onLoad = onLoad,
    }
}
