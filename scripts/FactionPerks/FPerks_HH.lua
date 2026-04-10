--[[
    HH:
        FPerks_HH1_Passive          - +5 Personality, +10 Speechcraft
        FPerks_HH2_Passive          - +15 Personality, +25 Speechcraft, +25 Illusion
        FPerks_HH3_Passive          - +25 Personality, +50 Mercantile
        FPerks_HH4_Passive          - +25 Personality, +75 Speechcraft

    Merchant effects (applied during active conversation via UiModeChanged,
    removed when dialogue closes). Applied by global script.

        Rank 1:  +10 Disposition / -5  Mercantile
        Rank 2:  +25 Disposition / -10 Mercantile  (total)
        Rank 3:  +50 Disposition / -15 Mercantile  (total)
        Rank 4: +100 Disposition / -20 Mercantile  (total)

    DOWNSIDE at P4: -25 Disposition with all NPCs.
    Applied via UiModeChanged on interaction, removed when dialogue closes.
    Same event system as merchant effects - no global polling needed.
]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local storage    = require('openmw.storage')

local perkStore = storage.playerSection("FactionPerks")

-- ============================================================
--  CORE HELPERS
-- ============================================================

local R = interfaces.ErnPerkFramework.requirements

local function notExpelled(factionId)
    return R().custom(function()
        return not types.NPC.isExpelled(self, factionId)
    end, "Must not be expelled from " .. factionId)
end

-- Create a table with all the Faction spell effects in it, each object is the perk of that rank
local perkTable = {
    [1] = { passive = {"FPerks_HH1_Passive"} },
    [2] = { passive = {"FPerks_HH2_Passive"} },
    [3] = { passive = {"FPerks_HH3_Passive"} },
    [4] = { passive = {"FPerks_HH4_Passive"} },
}

-- Increase the rank of the PerkTable, applying the new effects, and removing the old one.
local function setRank(NewRank)
-- Removes all other effects by iterating through the table, then for each object within THAT table, runs through those

    -- Removing
    for _, rankData in pairs(perkTable) do
    -- Remove spell effects
        if rankData.passive then --If the object in that table location is a passive (spell effect) run a command to remove it
            for i = 1, #rankData.passive do
                types.Actor.spells(self):remove(rankData.passive[i])
            end
        end
    end

-- Stop here if no rank (used for onRemove)
    if not NewRank or not perkTable[NewRank] then return end

    local rankData = perkTable[NewRank]

    -- Add spell effects
    if rankData.passive then --If the object in that table location is a passive (spell effect) run a command to add it
        for i = 1, #rankData.passive do
            types.Actor.spells(self):add(rankData.passive[i])
        end
    end
end

-- ============================================================
--  HLAALU DIALOGUE EFFECTS
--  Two separate effects are applied on NPC interaction and
--  removed when dialogue closes, both via UiModeChanged:
--
--  1. MERCHANT BUFF - Disposition and Mercantile bonus applied
--     to merchants only, scaling with perk rank.
--
--  2. GLOBAL DISP DOWNSIDE (P4 only) - -25 Disposition applied
--     to every NPC the player speaks to while holding P4.
--     Because both effects target the current NPC, they are
--     tracked and removed independently so they never conflict.
-- ============================================================

local HH_DISP = { 10, 25, 50, 100 }
local HH_MERC = { -5, -10, -15, -20 }
local HH_P4_PENALTY = -25   -- global disp downside

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

-- Global disp downside tracking
local hhPenaltyNpc     = nil
local hhHasPenalty     = false   -- true when P4 is held

local function isMerchant(actor)
    if not types.NPC.objectIsInstance(actor) then return false end
    local rec = types.NPC.record(actor)
    return rec and rec.baseGold > 0
end

local function hhTargetValues()
    local rank = perkStore:get("hh_rank") or 0
    if rank == 0 then return 0, 0 end
    return HH_DISP[rank], HH_MERC[rank]
end

-- Apply merchant buff to the given NPC
local function hhApplyMerchant(npc)
    local d, m = hhTargetValues()
    if d == 0 and m == 0 then return end
    core.sendGlobalEvent("FPerks_HH_ApplyMerchant", { npc = npc, disp = d, merc = m })
    hhCurrentNpc  = npc
    hhCurrentDisp = d
    hhCurrentMerc = m
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

-- Apply P4 penalty to the given NPC
local function hhApplyPenalty(npc)
    if not hhHasPenalty then return end
    core.sendGlobalEvent("FPerks_HH_ApplyMerchant", { npc = npc, disp = HH_P4_PENALTY, merc = 0 })
    hhPenaltyNpc = npc
end

-- Remove P4 penalty from the current NPC
local function hhRemovePenalty()
    if not hhPenaltyNpc then return end
    core.sendGlobalEvent("FPerks_HH_RemoveMerchant", { npc = hhPenaltyNpc, disp = HH_P4_PENALTY, merc = 0 })
    hhPenaltyNpc = nil
end

local function hhOnUiModeChanged(data)
    local rank = perkStore:get("hh_rank") or 0
    if rank == 0 then return end

    if not data.newMode then
        -- Dialogue closed - remove both effects from whoever had them
        hhRemoveMerchant()
        hhRemovePenalty()
        return
    end

    if HH_TALK_MODES[data.newMode] and data.arg then
        local npc = data.arg

        -- Merchant buff: apply to new NPC if they're a merchant
        if npc ~= hhCurrentNpc then
            hhRemoveMerchant()
            if isMerchant(npc) then
                hhApplyMerchant(npc)
            end
        end

        -- P4 penalty: apply to every NPC
        if npc ~= hhPenaltyNpc then
            hhRemovePenalty()
            hhApplyPenalty(npc)
        end
    end
end

local function hhRankUp(rank)
    local old = perkStore:get("hh_rank") or 0
    if old >= rank then return end
    perkStore:set("hh_rank", rank)
end

local function hhRankDown(rank)
    local cur = perkStore:get("hh_rank") or 0
    if cur < rank then return end
    hhRemoveMerchant()
    hhRemovePenalty()
    perkStore:set("hh_rank", rank - 1)
end

-- ============================================================
--  HOUSE HLAALU
--  Primary attribute: Personality
--  Scaling: Speechcraft, Illusion, Mercantile
--  Special: merchant Disposition boost + Mercantile debuff (P1-P4),
--           DOWNSIDE at P4: -25 Disposition with all NPCs
-- ============================================================

local hh1_id = ns .. "_hh_courtesies"
interfaces.ErnPerkFramework.registerPerk({
    id = hh1_id,
    localizedName = "Hlaalu Courtesies",
    --hidden = true,
    localizedDescription = "The formal pleasantries of Great House Hlaalu open many doors. "
        .. "Merchants warm to you and find their resolve to haggle weakened.\n "
        .. "(+5 Personality, +10 Speechcraft, "
        .. "merchants +10 Disposition / -5 Mercantile while speaking)",
    art = "textures\\levelup\\healer", cost = 1,
    requirements = {
        R().minimumFactionRank('hlaalu', 0),
        R().minimumLevel(1),
        notExpelled('hlaalu')
    },
    onAdd = function()
        setRank(1)
        hhRankUp(1)
    end,
    onRemove = function()
        setRank(nil)
        hhRankDown(1)
    end,
})

local hh2_id = ns .. "_hh_silver_tongue"
interfaces.ErnPerkFramework.registerPerk({
    id = hh2_id,
    localizedName = "Silver Tongue",
    --hidden = true,
    localizedDescription = "Your words carry weight. Merchants sense your confidence "
        .. "and their prices soften further.\n "
        .. "Requires Hlaalu Courtesies. "
        .. "(+15 Personality, +25 Speechcraft, +25 Illusion, "
        .. "merchants +25 Disposition / -10 Mercantile total while speaking)",
    art = "textures\\levelup\\healer", cost = 2,
    requirements = {
        R().hasPerk(hh1_id),
        R().minimumFactionRank('hlaalu', 3),
        R().minimumAttributeLevel('personality', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        hhRankUp(2)
    end,
    onRemove = function()
        setRank(nil)
        hhRankDown(2)
    end,
})

local hh3_id = ns .. "_hh_trade_acumen"
interfaces.ErnPerkFramework.registerPerk({
    id = hh3_id,
    localizedName = "Trade Acumen",
    --hidden = true,
    localizedDescription = "Merchants treat you as one of their own, dropping their guard further.\n "
        .. "Requires Silver Tongue. "
        .. "(+25 Personality, +50 Mercantile, "
        .. "merchants +50 Disposition / -15 Mercantile total while speaking)",
    art = "textures\\levelup\\healer", cost = 3,
    requirements = {
        R().hasPerk(hh2_id),
        R().minimumFactionRank('hlaalu', 6),
        R().minimumAttributeLevel('personality', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
        hhRankUp(3)
    end,
    onRemove = function()
        setRank(nil)
        hhRankDown(3)
    end,
})

local hh4_id = ns .. "_hh_councillors_ear"
interfaces.ErnPerkFramework.registerPerk({
    id = hh4_id,
    localizedName = "Councillor's Ear",
    --hidden = true,
    localizedDescription = "A Councillor of House Hlaalu considers you a trusted confidant. "
        .. "Merchants can barely bring themselves to refuse you anything.\n "
        .. "But your reputation precedes you everywhere now - people smile to your face "
        .. "and count their fingers behind their back. Handing them pocket change "
        .. "is an insult, not a gesture.\n "
        .. "Requires Trade Acumen. "
        .. "(+25 Personality, +75 Speechcraft, "
        .. "merchants +100 Disposition / -20 Mercantile total while speaking.\n "
        .. "DOWNSIDE: -25 Disposition with all NPCs.)",
    art = "textures\\levelup\\healer", cost = 4,
    requirements = {
        R().hasPerk(hh3_id),
        R().minimumFactionRank('hlaalu', 9),
        R().minimumAttributeLevel('personality', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        hhRankUp(4)
        hhHasPenalty = true
    end,
    onRemove = function()
        setRank(nil)
        hhHasPenalty = false
        hhRankDown(4)
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================
return {
    eventHandlers = {
        UiModeChanged = hhOnUiModeChanged,
    },
}
