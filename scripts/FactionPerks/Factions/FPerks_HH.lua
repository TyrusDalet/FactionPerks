--[[
    HH:
        FPerks_HH1_Passive          - +3 Personality, +3 Agility, +5 Mercantile, +5 Speechcraft
        FPerks_HH2_Passive          - +5 Personality, +5 Agility, +10 Mercantile, +10 Speechcraft
        FPerks_HH3_Passive          - +10 Personality, +10 Agility, +18 Mercantile, +18 Speechcraft
        FPerks_HH4_Passive          - +15 Personality, +15 Agility, +25 Mercantile, +25 Speechcraft

    Honour The Great House (P1+): Guile of the Hlaalu
        Merchant Disposition bonus and Mercantile debuff scale
        continuously with faction reputation via honourScale.
        At rep cap:  +100 Disposition / -30 Mercantile
        Post-cap:    continues growing at 30% of pre-cap rate.
        Applied during active conversation via UiModeChanged,
        removed when dialogue closes. Routed through global script
        since modifyBaseDisposition is global-only.
        Shows "You Honour House Hlaalu." on first merchant
        interaction per conversation.
]]

local ns         = require("scripts.FactionPerks.namespace")
local utils      = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local GUILD        = utils.FACTION_GROUPS.hlaalu
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local ui         = require('openmw.ui')
local localization = core.l10n(ns)

-- ============================================================
--  CORE HELPERS
-- ============================================================

local R = utils.requirements

-- Create a table with all the Faction spell effects in it, each object is the perk of that rank
local perkTable = {
    [1] = { attributes = { personality=3,  agility=3  }, skills = { mercantile=5,  speechcraft=5 } },
    [2] = { attributes = { personality=5,  agility=5  }, skills = { mercantile=10, speechcraft=10 } },
    [3] = { attributes = { personality=10, agility=10 }, skills = { mercantile=18, speechcraft=18 } },
    [4] = { attributes = { personality=15, agility=15 }, skills = { mercantile=25, speechcraft=25 } },
}

local appliedStats = { attributes = {}, skills = {} }

-- Perk id prep
local hh1_id = ns .. "_hh_courtesies"
local hh2_id = ns .. "_hh_silver_tongue"
local hh3_id = ns .. "_hh_trade_acumen"
local hh4_id = ns .. "_hh_councillors_ear"

local setRank = utils.makeSetRank(perkTable, nil, appliedStats)

-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Great House Hlaalu Perks"

local function getHHRank()
    if R().hasPerk(hh4_id).check() then return 4 end
    if R().hasPerk(hh3_id).check() then return 3 end
    if R().hasPerk(hh2_id).check() then return 2 end
    if R().hasPerk(hh1_id).check() then return 1 
    else return 0
    end
end

local function reportAAM()
    if not interfaces.AAM then return end
    local rank = getHHRank() -- your faction's getXXRank() function
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
--  HLAALU DIALOGUE EFFECTS
--  Two separate effects are applied on NPC interaction and
--  removed when dialogue closes, both via UiModeChanged:
--
--  1. GUILE OF THE HLAALU - Honour The Great House (P1+)
--     Merchant Disposition bonus and Mercantile debuff scale
--     continuously with faction reputation rather than jumping
--     at perk tiers. Reaches the P4 values at the rep cap.
--     Beyond the cap growth slows significantly.
--     Shows "You Honour House Hlaalu." on first application
--     each conversation.
--
--     At rep cap:  +100 Disposition / -30 Mercantile
--     Formula scales linearly from 0 to cap, then trickles.
--
--  Both effects route through global script since
--  modifyBaseDisposition is global-only.
-- ============================================================

-- Maximum values reached at rep cap
local HH_DISP_MAX  = 100
local HH_MERC_MAX  = -30
local hhHasGuile   = false

local function hhScaledValues()
    -- Returns disposition bonus and mercantile debuff scaled by
    -- faction reputation. Uses shared honourScale for consistent
    -- pre/post-cap behaviour across all Honour The Great House effects.
    local scale = utils.honourScale('hlaalu')
    return math.floor(HH_DISP_MAX * scale),
           math.floor(HH_MERC_MAX * scale)
end

local HH_TALK_MODES = {
    Barter         = true,
    Dialogue       = true,
    Training       = true,
    SpellBuying    = true,
    MerchantRepair = true,
    Enchanting     = true,
    Companion      = true,
}

-- Merchant buff tracking
local hhCurrentNpc  = nil
local hhCurrentDisp = 0
local hhCurrentMerc = 0

-- Original TRADE_SERVICES table - checks servicesOffered fields so that
-- trainers, enchanters, etc. who have baseGold but don't barter goods
-- are correctly excluded from the Hlaalu merchant buff.
local TRADE_SERVICES = {
    Barter      = true, Weapon      = true, Armor       = true,
    Clothing    = true, Books       = true, Ingredients = true,
    Picks       = true, Probes      = true, Lights      = true,
    Apparatus   = true, RepairItems = true, Misc        = true,
    Potions     = true, MagicItems  = true,
}

local function isMerchant(actor)
    if not types.NPC.objectIsInstance(actor) then return false end
    local services = types.NPC.record(actor).servicesOffered
    if not services then return false end
    for service, _ in pairs(TRADE_SERVICES) do
        if services[service] then return true end
    end
    return false
end

local hhMerchantMsgShown = false   -- show "You Honour House Hlaalu." once per conversation

local function hhApplyMerchant(npc)
    if not hhHasGuile then return end
    local d, m = hhScaledValues()
    if d == 0 and m == 0 then return end
    core.sendGlobalEvent("FPerks_HH_ApplyMerchant", { npc = npc, disp = d, merc = m })
    hhCurrentNpc  = npc
    hhCurrentDisp = d
    hhCurrentMerc = m
    if not hhMerchantMsgShown then
        ui.showMessage(localization("hh_honourMessage", {}))
        hhMerchantMsgShown = true
    end
end

-- Remove merchant buff from the current NPC
local function hhRemoveMerchant()
    if not hhCurrentNpc then return end
    core.sendGlobalEvent("FPerks_HH_RemoveMerchant", {
        npc  = hhCurrentNpc,
        disp = hhCurrentDisp,
        merc = hhCurrentMerc,
    })
    hhCurrentNpc  = nil
    hhCurrentDisp = 0
    hhCurrentMerc = 0
end

local function hhOnUiModeChanged(data)
    if not hhHasGuile then return end

    if not data.newMode then
        -- Dialogue closed - remove merchant buff and reset msg flag
        hhRemoveMerchant()
        hhMerchantMsgShown = false
        return
    end

    if HH_TALK_MODES[data.newMode] and data.arg then
        local npc = data.arg
        if npc ~= hhCurrentNpc then
            hhRemoveMerchant()
            if isMerchant(npc) then
                hhApplyMerchant(npc)
            end
        end
    end
end

local function hhClearEffects()
    -- Strips active dialogue effects on respec or expulsion.
    hhRemoveMerchant()
    hhHasGuile         = false
    hhMerchantMsgShown = false
end

-- ============================================================
--  HOUSE HLAALU
--  Primary attributes: Personality, Agility
--  Scaling: Mercantile, Speechcraft
--  Honour The Great House (P1+): Guile of the Hlaalu -
--           merchant Disposition/Mercantile scales with faction
--           reputation via honourScale.
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = hh1_id,
    localizedName = "Hlaalu Courtesies",
    category = {"Great Houses", "House Hlaalu", 1},
    localizedFlavour = "The formal pleasantries of Great House Hlaalu open many doors. "
        .. "Those who deal with you find their instinct to haggle subtly weakened.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+3 Personality, +3 Agility, "
        .. "+5 Mercantile, +5 Speechcraft)\f"
        .. "Effect 2: \n Guile of the Hlaalu: Disposition with merchants and their Mercantile skill "
        .. "scale with Hlaalu reputation. At reputation cap: +100 Disposition, -30 Mercantile.",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("hlaalu",0),
        R().minimumLevel(1)
    },
    onAdd = function()
        setRank(1)
        reportAAM()
        hhHasGuile = true
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        hhClearEffects()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = hh2_id,
    localizedName = "Silver Tongue",
    category = {"Great Houses", "House Hlaalu", 2},
    localizedFlavour = "Your words carry weight. Merchants sense your confidence "
        .. "and their prices soften further.",
    localizedDescription = "Grants the following stats: (+5 Personality, +5 Agility, "
        .. "+10 Mercantile, +10 Speechcraft)",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R().hasPerk(hh1_id),
        FactionGroupRank("hlaalu",3),
        R().minimumAttributeLevel('personality', 40),
        R().minimumLevel(5),
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
    id = hh3_id,
    localizedName = "Trade Acumen",
    category = {"Great Houses", "House Hlaalu", 3},
    localizedFlavour = "Merchants treat you as one of their own, dropping their guard further.",
    localizedDescription = "Grants the following stats: (+10 Personality, +10 Agility, "
        .. "+18 Mercantile, +18 Speechcraft)",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R().hasPerk(hh2_id),
        FactionGroupRank("hlaalu",6),
        R().minimumAttributeLevel('personality', 50),
        R().minimumLevel(10),
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
    id = hh4_id,
    localizedName = "Councillor's Ear",
    category = {"Great Houses", "House Hlaalu", 4},
    localizedFlavour = "A Councillor of House Hlaalu considers you a trusted confidant. "
        .. "Merchants can barely bring themselves to refuse you anything.",
    localizedDescription = "Grants the following stats: (+15 Personality, +15 Agility, "
        .. "+25 Mercantile, +25 Speechcraft)",
    hidden = perkHidden(GUILD, 9, 15),
    art = "textures\\levelup\\healer",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        R().hasPerk(hh3_id),
        FactionGroupRank("hlaalu",9),
        R().minimumAttributeLevel('personality', 75),
        R().minimumLevel(15),
    },
    onAdd    = function()
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
        UiModeChanged = hhOnUiModeChanged,
        onSave = onSave,
        onLoad = onLoad,
    },
}
