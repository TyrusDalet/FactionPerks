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
        "strong levitate"             Vanilla spell (P1)
        "mark"                        Vanilla spell (P2)
        "recall"                      Vanilla spell (P2)

    Honour The Great House (P1+): Wit of the Telvanni
        When the player activates a Cast on Use enchanted item, the
        self-targeting effects of the enchantment are augmented via
        activeEffects:modify + cleanup timer.
        Only CastOnUse enchantments are affected - Constant Effect
        is always active, CastOnStrike is weapon-triggered, and
        CastOnce destroys the item.
        Only self-range effects are augmented - targeting others
        is excluded to avoid cross-actor complexity.
        Application is delayed 0.1s via async so the engine has
        time to process the enchantment before we augment its effects.
        Cleanup fires at duration - 0.1s to reverse each bonus.
        At rep cap:  +150% of base magnitude (total 250% effect)
        Post-cap:    continues growing at 30% of pre-cap rate.
        Shows "You Honour the Wit of House Telvanni." on first
        enchantment cast per session while the perk is held.

        Detection uses AnimationController text key to catch cast
        start, and SkillProgression to confirm success before
        applying augmentation - consistent with MG spell refund.
]]

local ns          = require("scripts.FactionPerks.namespace")
local utils       = require("scripts.FactionPerks.utils")
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local ui          = require('openmw.ui')
local core        = require('openmw.core')
local async       = require('openmw.async')

local R = interfaces.ErnPerkFramework.requirements

local perkTable = {
    [1] = { passive = {"FPerks_HT1_Passive"} },
    [2] = { passive = {"FPerks_HT2_Passive"} },
    [3] = { passive = {"FPerks_HT3_Passive"} },
    [4] = { passive = {"FPerks_HT4_Passive"} },
}

local setRank = utils.makeSetRank(perkTable, nil)

-- ============================================================
--  HOUSE TELVANNI
--  Primary attribute: Intelligence (P1-P3), Willpower (P4)
--  Scaling: Enchant, Alchemy, Spell Absorption,
--           Fortify Maximum Magicka
--  Honour The Great House (P1+): Wit of the Telvanni -
--           Cast on Use enchantment self-effects are augmented
--           based on faction rep. At rep cap: +150% extra
--           magnitude (total 250% of base). Beyond cap: trickles.
--  Special: Strong Levitate (P1), Mark + Recall (P2),
--           Restore Magicka abilities (P3 + P4 stacking).
-- ============================================================

-- ============================================================
--  WIT OF THE TELVANNI - Honour The Great House
--
--  When the player activates a Cast on Use enchanted item,
--  self-range effects are augmented via activeEffects:modify,
--  scaled by honourScale.
--
--
--  At rep cap:  +150% extra magnitude (total 250% of base)
--  Post-cap:    continues at 30% of pre-cap rate (honourScale)
-- ============================================================

local hasWitOfTelvanni = false
local telvMsgShown     = false

-- ============================================================
--  Effect classification tables - unchanged from potion version.
--  See original header comments for rationale per category.
-- ============================================================

local FORTIFY_ATTR = { ["fortifyattribute"] = true }
local FORTIFY_SKILL = { ["fortifyskill"] = true }
local RESTORE_DYN = {
    ["restorehealth"]  = "health",
    ["restoremagicka"] = "magicka",
    ["restorefatigue"] = "fatigue",
}

local function applyFortifyAttr(attrId, bonus)
    local stat = types.Actor.stats.attributes[attrId]
    if stat then stat(self).modifier = stat(self).modifier + bonus end
end

local function applyFortifySkill(skillId, bonus)
    local stat = types.NPC.stats.skills[skillId]
    if stat then stat(self).modifier = stat(self).modifier + bonus end
end

local function applyRestoreDyn(dynKey, bonus, duration)
    local total = bonus * duration
    if total <= 0 then return end
    local dyn = types.Actor.stats.dynamic[dynKey]
    if dyn then
        local s = dyn(self)
        s.current = math.min(s.current + total, s.base + s.modifier)
    end
end

-- ============================================================
--  ENCHANTMENT AUGMENTATION
--  Called from the enchant skill handler after a confirmed
--  successful Cast on Use activation.
-- ============================================================

local function TelvanniWitEnchant(item)
    if not hasWitOfTelvanni then return end
    if not item or not item:isValid() then return end

    -- Only Cast on Use enchantments
    local record = nil
    for _, t in ipairs({types.Weapon, types.Armor, types.Clothing,
                        types.Miscellaneous, types.Book}) do
        if t.objectIsInstance(item) then
            local r = t.record(item)
            if r and r.enchant and r.enchant ~= "" then
                record = core.magic.enchantments.records[r.enchant]
            end
            break
        end
    end

    if not record then return end
    if record.type ~= core.magic.ENCHANTMENT_TYPE.CastOnUse then return end
    if not record.effects then return end

    local scale = utils.honourScale('telvanni') * 1.5
    if scale <= 0 then return end

    -- Build bonus list from self-range effects only
    local bonuses = {}
    for _, effectParams in ipairs(record.effects) do
        -- Only augment self-targeting effects
        if effectParams.range == core.magic.RANGE.Self then
            local baseMag = (effectParams.magnitudeMin + effectParams.magnitudeMax) / 2
            local bonus   = math.floor(baseMag * scale)
            if bonus > 0 then
                bonuses[#bonuses + 1] = {
                    id         = effectParams.id,
                    extraParam = effectParams.affectedAttribute
                              or effectParams.affectedSkill
                              or nil,
                    bonus      = bonus,
                    duration   = effectParams.duration,
                }
            end
        end
    end

    if #bonuses == 0 then return end
    local timer = 0.1

    async:newUnsavableSimulationTimer(timer, function()
        local activeEffects = types.Actor.activeEffects(self)

        for _, b in ipairs(bonuses) do
            local dynKey = RESTORE_DYN[b.id]

            if FORTIFY_ATTR[b.id] and b.extraParam then
                applyFortifyAttr(b.extraParam, b.bonus)
                async:newUnsavableSimulationTimer(b.duration - timer, function()
                    applyFortifyAttr(b.extraParam, -b.bonus)
                end)

            elseif FORTIFY_SKILL[b.id] and b.extraParam then
                applyFortifySkill(b.extraParam, b.bonus)
                async:newUnsavableSimulationTimer(b.duration - timer, function()
                    applyFortifySkill(b.extraParam, -b.bonus)
                end)

            elseif dynKey then
                applyRestoreDyn(dynKey, b.bonus, b.duration)

            else
                if b.extraParam then
                    activeEffects:modify(b.bonus, b.id, b.extraParam)
                else
                    activeEffects:modify(b.bonus, b.id)
                end
                async:newUnsavableSimulationTimer(b.duration - timer, function()
                    if b.extraParam then
                        activeEffects:modify(-b.bonus, b.id, b.extraParam)
                    else
                        activeEffects:modify(-b.bonus, b.id)
                    end
                end)
            end
        end

        if not telvMsgShown then
            ui.showMessage("You Honour the Wit of House Telvanni.")
            telvMsgShown = true
        end
    end)
end

-- ============================================================
--  ENCHANT SKILL HANDLER
--  Fires only on successful Cast on Use activation since the
--  Enchant skill only advances on success. This is our
--  reliable success gate, consistent with MG spell refund.
-- ============================================================

interfaces.SkillProgression.addSkillUsedHandler(function(skillId, params)
    if skillId ~= "enchant"  then return end
    if not hasWitOfTelvanni  then return end

    -- Read directly here instead of relying on animation caching —
    -- Cast on Use enchantments don't use the spellcast animation group
    local item = types.Actor.getSelectedEnchantedItem(self)
    print("HT currentItem: " .. tostring(item))
    if not item then return end

    TelvanniWitEnchant(item)
end)

-- ============================================================
--  HOUSE TELVANNI PERKS
-- ============================================================

local ht1_id = ns .. "_ht_uninvited_student"
interfaces.ErnPerkFramework.registerPerk({
    id = ht1_id,
    localizedName = "Uninvited Student",
    localizedDescription = "House Telvanni does not recruit - it tolerates those strong enough "
        .. "to push their way in. You have done so. For now, that is enough.\n "
        .. "(+5 Intelligence, +10 Enchant, +10 Alchemy, +10 Spell Absorption, "
        .. "grants Strong Levitate)\n\n"
        .. "Honour the Wit of the Great House Telvanni: Cast on Use enchantments "
        .. "that target yourself are augmented based on your Telvanni reputation.\n"
        .. "At reputation cap: effects are 250%% of their base magnitude.",
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('telvanni', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        setRank(1)
        types.Actor.spells(self):add("strong levitate")
        hasWitOfTelvanni = true
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("strong levitate")
        hasWitOfTelvanni = false
        telvMsgShown = false
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
        types.Actor.spells(self):add("FPerks_HT3_Restore_Magicka_1")
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("FPerks_HT3_Restore_Magicka_1")
    end,
})

local ht4_id = ns .. "_ht_telvanni_lord"
interfaces.ErnPerkFramework.registerPerk({
    id = ht4_id,
    localizedName = "Telvanni Lord",
    localizedDescription = "You are acknowledged by the Telvanni masters - a rare concession "
        .. "from those who acknowledge no one. The heights are yours to claim.\n "
        .. "Requires Self-Made Power. "
        .. "(+25 Willpower, +75 Enchant, +75 Alchemy, +75 Spell Absorption, "
        .. "Fortify Maximum Magicka 1.0x Intelligence, "
        .. "additional Restore Magicka 2pt/s)",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(ht3_id),
        R().minimumFactionRank('telvanni', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
    end,
    onRemove = function()
        setRank(nil)
    end,
})

return {}