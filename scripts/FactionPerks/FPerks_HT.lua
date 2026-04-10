--[[
    HT:
        FPerks_HT1_Passive          - +5 Intelligence, +10 Enchant, +10 Alchemy,
                                      +10 Spell Absorption
        FPerks_HT2_Passive          - +15 Intelligence, +25 Enchant, +25 Alchemy,
                                      +25 Spell Absorption
        FPerks_HT3_Passive          - +25 Intelligence, +50 Enchant, +50 Alchemy,
                                      +50 Spell Absorption,
                                      Fortify Maximum Magicka 0.5x Intelligence (magnitude 5)
        FPerks_HT4_Passive          - +25 Willpower, +75 Enchant, +75 Alchemy,
                                      +75 Spell Absorption,
                                      Fortify Maximum Magicka 1.0x Intelligence (magnitude 10)

    Non-table spells (granted once, not removed on rank-up):
        "strong levitate"           Vanilla spell (P1)
        "mark"                      Vanilla spell (P2)
        "recall"                    Vanilla spell (P2)

    DOWNSIDE at P4: -30 Disposition with all NPCs.
    Applied via UiModeChanged on interaction, removed when dialogue closes.
    Same event system as Hlaalu merchant effects - no global polling needed.
]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local storage    = require('openmw.storage')

local perkStore = storage.playerSection("FactionPerks")

local R = interfaces.ErnPerkFramework.requirements

local function notExpelled(factionId)
    return R().custom(function()
        return not types.NPC.isExpelled(self, factionId)
    end, "Must not be expelled from " .. factionId)
end

local perkTable = {
    [1] = { passive = {"FPerks_HT1_Passive"} },
    [2] = { passive = {"FPerks_HT2_Passive"} },
    [3] = { passive = {"FPerks_HT3_Passive"} },
    [4] = { passive = {"FPerks_HT4_Passive"} },
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
--  HOUSE TELVANNI
--  Primary attribute: Intelligence (P1-P3), Willpower (P4)
--  Scaling: Enchant, Alchemy, Spell Absorption,
--           Fortify Maximum Magicka
--  Special: Strong Levitate (P1), Mark + Recall (P2),
--           Restore Magicka abilities (P3 + P4 stacking).
--  DOWNSIDE at P4: -30 Disposition with all NPCs,
--           applied on interaction via UiModeChanged.
-- ============================================================

-- ============================================================
--  TELVANNI GLOBAL DISP DOWNSIDE
--  Applied to every NPC the player speaks to while P4 is held.
--  Removed the moment dialogue closes. Reuses the Hlaalu
--  global events since the underlying operation is identical.
-- ============================================================

local HT_TALK_MODES = {
    Barter         = true,
    Dialogue       = true,
    Training       = true,
    SpellBuying    = true,
    MerchantRepair = true,
    Enchanting     = true,
    Companion      = true,
}

local HT_PENALTY    = -30
local htPenaltyNpc  = nil
local htHasPenalty  = false   -- true when P4 is held

local function htApplyPenalty(npc)
    if not htHasPenalty then return end
    core.sendGlobalEvent("FPerks_HH_ApplyMerchant", { npc = npc, disp = HT_PENALTY, merc = 0 })
    htPenaltyNpc = npc
end

local function htRemovePenalty()
    if not htPenaltyNpc then return end
    core.sendGlobalEvent("FPerks_HH_RemoveMerchant", { npc = htPenaltyNpc, disp = HT_PENALTY, merc = 0 })
    htPenaltyNpc = nil
end

local function htOnUiModeChanged(data)
    if not htHasPenalty then return end

    if not data.newMode then
        htRemovePenalty()
        return
    end

    if HT_TALK_MODES[data.newMode] and data.arg then
        local npc = data.arg
        if npc == htPenaltyNpc then return end
        htRemovePenalty()
        if types.NPC.objectIsInstance(npc) then
            htApplyPenalty(npc)
        end
    end
end

local ht1_id = ns .. "_ht_uninvited_student"
interfaces.ErnPerkFramework.registerPerk({
    id = ht1_id,
    localizedName = "Uninvited Student",
    localizedDescription = "House Telvanni does not recruit - it tolerates those strong enough "
        .. "to push their way in. You have done so. For now, that is enough.\n "
        .. "(+5 Intelligence, +10 Enchant, +10 Alchemy, +10 Spell Absorption, "
        .. "grants Strong Levitate)",
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('telvanni', 0),
        R().minimumLevel(1),
        notExpelled('telvanni')
    },
    onAdd = function()
        setRank(1)
        types.Actor.spells(self):add("strong levitate")
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("strong levitate")
    end,
})

local ht2_id = ns .. "_ht_tower_sorcery"
interfaces.ErnPerkFramework.registerPerk({
    id = ht2_id,
    localizedName = "Tower Sorcery",
    localizedDescription = "Telvanni wizards are defined by their mastery of enchantment. "
        .. "You have begun to understand the principles that animate their towers and servants.\n "
        .. "Requires Uninvited Student. "
        .. "(+15 Intelligence, +25 Enchant, +25 Alchemy, +25 Spell Absorption, "
        .. "grants Mark and Recall)",
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(ht1_id),
        R().minimumFactionRank('telvanni', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        types.Actor.spells(self):add("mark")
        types.Actor.spells(self):add("recall")
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("mark")
        types.Actor.spells(self):remove("recall")
    end,
})

local ht3_id = ns .. "_ht_self_made_power"
interfaces.ErnPerkFramework.registerPerk({
    id = ht3_id,
    localizedName = "Self-Made Power",
    localizedDescription = "House Telvanni respects only power earned, never granted. "
        .. "You have shaped yourself through relentless study.\n "
        .. "Requires Tower Sorcery. "
        .. "(+25 Intelligence, +50 Enchant, +50 Alchemy, +50 Spell Absorption, "
        .. "Fortify Maximum Magicka 0.5x Intelligence, Restore Magicka 1pt/s)",
    art = "textures\\levelup\\mage", cost = 3,
    requirements = {
        R().hasPerk(ht2_id),
        R().minimumFactionRank('telvanni', 6),
        R().minimumAttributeLevel('intelligence', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
    end,
    onRemove = function()
        setRank(nil)
    end,
})

local ht4_id = ns .. "_ht_telvanni_lord"
interfaces.ErnPerkFramework.registerPerk({
    id = ht4_id,
    localizedName = "Telvanni Lord",
    localizedDescription = "You are acknowledged by the Telvanni masters - a rare concession "
        .. "from those who acknowledge no one. The heights are yours to claim.\n "
        .. "But you have become something other people find deeply unsettling. "
        .. "Your isolation and accumulated power have made you alien - ordinary folk "
        .. "sense it before you even open your mouth, and they want nothing to do with you.\n "
        .. "Requires Self-Made Power. "
        .. "(+25 Willpower, +75 Enchant, +75 Alchemy, +75 Spell Absorption, "
        .. "Fortify Maximum Magicka 1.0x Intelligence, "
        .. "additional Restore Magicka 1pt/s.\n "
        .. "DOWNSIDE: -30 Disposition with all NPCs.)",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(ht3_id),
        R().minimumFactionRank('telvanni', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        htHasPenalty = true
    end,
    onRemove = function()
        setRank(nil)
        htHasPenalty = false
        htRemovePenalty()
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================
return {
    eventHandlers = {
        UiModeChanged = htOnUiModeChanged,
    },
}
