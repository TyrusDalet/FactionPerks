--[[
    HT:
        FPerks_HT1_Passive          - +3 Intelligence, +3 Willpower,
                                      +5 Enchant, +5 Conjuration
        FPerks_HT2_Passive          - +5 Intelligence, +5 Willpower,
                                      +10 Enchant, +10 Conjuration
        FPerks_HT3_Passive          - +10 Intelligence, +10 Willpower,
                                      +18 Enchant, +18 Conjuration,
                                      Fortify Maximum Magicka 0.5x Intelligence (magnitude 5),
                                      Restore Magicka 1pt/s
        FPerks_HT4_Passive          - +15 Intelligence, +15 Willpower,
                                      +25 Enchant, +25 Conjuration,
                                      Fortify Maximum Magicka 1.0x Intelligence (magnitude 10),
                                      Restore Magicka 2pt/s

    Non-table spells (granted once, not removed on rank-up):
        "bound helm"                Vanilla spell (P1)
        "bound cuirass"             Vanilla spell (P1)
        "tranasa's spelltrap"       Vanilla spell (P2)

    Honour The Great House (P1+): Wit of the Telvanni

        CAST ON USE:
        Self-range non-harmful effects are augmented immediately.
        Cleanup uses activeSpells polling (durationLeft) rather than
        async timers so bonuses survive saves and loads correctly.
        The tracking table is persisted via onSave/onLoad.
        On load, the table is restored but bonuses are NOT re-applied
        (they are already in stat.modifier from the save file).

        CONSTANT EFFECT:
        Non-harmful effects on equipped CE items are augmented via
        stat.modifier (Fortify Health/Magicka/Fatigue and Fortify
        Attribute/Skill) or activeEffects:modify (everything else).
        Harmful effects are skipped entirely.
        The CE boost table is persisted via onSave/onLoad to prevent
        load stacking.

        All character-specific data is in onSave/onLoad.
        
]]

local ns          = "FactionPerks"
local utils       = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local safeAddSpell  = utils.safeAddSpell
local safeRemoveSpell = utils.safeRemoveSpell
local GUILD        = utils.FACTION_GROUPS.telvanni
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local ui          = require('openmw.ui')
local core        = require('openmw.core')
local CALCULATION = interfaces.ErnPerkFramework.CALCULATION

local R = utils.requirements()

local perkTable = {
    [1] = { attributes = { intelligence=3,  willpower=3  }, skills = { enchant=5,  conjuration=5 } },
    [2] = { attributes = { intelligence=5,  willpower=5  }, skills = { enchant=10, conjuration=10 } },
    [3] = { attributes = { intelligence=10, willpower=10 },
            skills = { enchant=18, conjuration=18 },
            passive = { "FPerks_HT3_Restore_Magicka_1" } },
    [4] = { attributes = { intelligence=15, willpower=15 },
            skills = { enchant=25, conjuration=25 },
            passive = { "FPerks_HT4_Restore_Magicka_2" } },
}

local appliedStats = { attributes = {}, skills = {} }

local setRank = utils.makeSetRank(perkTable, nil, appliedStats)

-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Great House Telvanni Perks"

local ht1_id = ns .. "_ht_uninvited_student"
local ht2_id = ns .. "_ht_tower_sorcery"
local ht3_id = ns .. "_ht_self_made_power"
local ht4_id = ns .. "_ht_telvanni_lord"

local function getHTRank()
    return utils.highestOwnedPerkRank({
        [1] = ht1_id,
        [2] = ht2_id,
        [3] = ht3_id,
        [4] = ht4_id,
    })
end

local reportAAM = utils.makeAAMReporter(FACTION_DISPLAY_NAME, perkTable, getHTRank)


-- ============================================================
--  WIT OF THE TELVANNI - shared state
-- ============================================================

local hasWitOfTelvanni   = false

--- Adds Wit of Telvanni's Cast on Use magnitude contribution to the framework resolver.
--- @param data table Calculation context containing baseValue and enchantment context.
--- @return number|nil bonus Additional magnitude to add, or nil when inactive.
local function telvanniWitCastOnUseContribution(data)
    if not hasWitOfTelvanni then return end
    local scale = utils.honourScale('telvanni') * 1.5
    if scale <= 0 then return end
    return data.baseValue * scale
end

--- Adds Wit of Telvanni's Constant Effect magnitude contribution to the framework resolver.
--- @param data table Calculation context containing baseValue and enchantment context.
--- @return number|nil bonus Additional magnitude to add, or nil when inactive.
local function telvanniWitConstantEffectContribution(data)
    if not hasWitOfTelvanni then return end
    local scale = math.min(utils.honourScale('telvanni'), 1.0)
    if scale <= 0 then return end
    return data.baseValue * scale
end

interfaces.ErnPerkFramework.registerCalculationHandler({
    id = "FactionPerks_telvanni_wit_cast_on_use_magnitude",
    calculation = CALCULATION.ENCHANT_CAST_ON_USE_SELF_EFFECT_MAGNITUDE,
    operation = "Addition",
    priority = 100,
}, telvanniWitCastOnUseContribution)

interfaces.ErnPerkFramework.registerCalculationHandler({
    id = "FactionPerks_telvanni_wit_constant_effect_magnitude",
    calculation = CALCULATION.ENCHANT_CONSTANT_EFFECT_SELF_EFFECT_MAGNITUDE,
    operation = "Addition",
    priority = 100,
}, telvanniWitConstantEffectContribution)

-- ============================================================
--  CHARACTER-SPECIFIC STATE (persisted via onSave/onLoad)
--
--  activeCastOnUseBonuses: keyed by item.recordId
--    Each entry: { bonuses = { {id, extraParam, bonus, path, dynKey} } }
--    Restored on load for expiry tracking only - bonuses are NOT
--    re-applied as they are already in stat.modifier from the save.
--
--  activeConstantBoosts: keyed by equipment slot number
--    Each entry: { itemId, bonuses = { {id, extraParam, bonus, path, dynKey} } }
--    Restored on load for slot-change detection only - same reasoning.
-- ============================================================

local activeCastOnUseBonuses = {}
local activeConstantBoosts   = {}
local castOnUsePollTimer     = 0
local CAST_ON_USE_POLL_INTERVAL = 0.5
local equipmentCheckTimer    = 0
local EQUIPMENT_CHECK_INTERVAL = 2.0
local lastHTCellId           = nil

-- ============================================================
--  EFFECT CLASSIFICATION TABLES
-- ============================================================

local FORTIFY_ATTR  = { ["fortifyattribute"] = true }
local FORTIFY_SKILL = { ["fortifyskill"]     = true }
local FORTIFY_DYN   = {
    ["fortifyhealth"]  = "health",
    ["fortifymagicka"] = "magicka",
    ["fortifyfatigue"] = "fatigue",
}
local RESTORE_DYN   = {
    ["restorehealth"]  = "health",
    ["restoremagicka"] = "magicka",
    ["restorefatigue"] = "fatigue",
}

-- ============================================================
--  STAT HELPER FUNCTIONS
-- ============================================================

--- Applies or reverses a Fortify Attribute style bonus via stat.modifier.
--- @param attrId string Attribute id.
--- @param bonus number Signed modifier delta.
local function applyFortifyAttr(attrId, bonus)
    local stat = types.Actor.stats.attributes[attrId]
    if stat then stat(self).modifier = stat(self).modifier + bonus end
end

--- Applies or reverses a Fortify Skill style bonus via stat.modifier.
--- @param skillId string Skill id.
--- @param bonus number Signed modifier delta.
local function applyFortifySkill(skillId, bonus)
    local stat = types.NPC.stats.skills[skillId]
    if stat then stat(self).modifier = stat(self).modifier + bonus end
end

--- Applies or reverses a Fortify dynamic-stat bonus and adjusts current value on gain.
--- @param dynKey string Dynamic stat key: health, magicka, or fatigue.
--- @param bonus number Signed modifier delta.
local function applyFortifyDyn(dynKey, bonus)
    local dyn = types.Actor.stats.dynamic[dynKey]
    if dyn then
        local s = dyn(self)
        s.modifier = s.modifier + bonus
        if bonus > 0 then
            s.current = s.current + bonus
        end
    end
end

--- Applies a Restore dynamic-stat bonus as an immediate lump sum.
--- @param dynKey string Dynamic stat key: health, magicka, or fatigue.
--- @param bonus number Restore magnitude per second.
--- @param duration number Effect duration in seconds.
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
--  SHARED ENCHANTMENT RECORD READER
-- ============================================================

local ENCHANTABLE_TYPES = {
    types.Weapon, types.Armor, types.Clothing,
    types.Miscellaneous, types.Book,
}

--- Reads the enchantment record from any enchantable item object.
--- @param item GameObject Item object.
--- @return table|nil enchantment Enchantment record, if present.
local function getEnchantmentRecord(item)
    if not item or not item:isValid() then return nil end
    for _, t in ipairs(ENCHANTABLE_TYPES) do
        if t.objectIsInstance(item) then
            local r = t.record(item)
            if r and r.enchant and r.enchant ~= "" then
                return core.magic.enchantments.records[r.enchant]
            end
            break
        end
    end
    return nil
end

--- Checks whether a magic effect is marked harmful in the effect records.
--- @param effectId string Magic effect id.
--- @return boolean harmful True when the effect should not be boosted.
local function isHarmful(effectId)
    local rec = core.magic.effects.records[effectId]
    return rec and rec.harmful == true
end

-- ============================================================
--  CAST ON USE - bonus application
-- ============================================================

--- Reverses tracked Cast on Use bonuses once the originating effect expires.
--- @param itemRecordId string Item record id used as the tracking key.
--- @param entry table Saved bonus entry.
local function reverseCastOnUseEntry(itemRecordId, entry)
    local activeEffects = types.Actor.activeEffects(self)
    for _, b in ipairs(entry.bonuses) do
        if b.path == "fortifyAttr" then
            applyFortifyAttr(b.extraParam, -b.bonus)
        elseif b.path == "fortifySkill" then
            applyFortifySkill(b.extraParam, -b.bonus)
        elseif b.path == "fortifyDyn" then
            applyFortifyDyn(b.dynKey, -b.bonus)
        else
            if b.extraParam then
                activeEffects:modify(-b.bonus, b.id, b.extraParam)
            else
                activeEffects:modify(-b.bonus, b.id)
            end
        end
    end
    activeCastOnUseBonuses[itemRecordId] = nil
    utils.debug(2, "HT", "Wit reversed CastOnUse bonus for " .. tostring(itemRecordId))
end

--- Checks active spells to see whether a Cast on Use bonus source is still active.
--- @param itemRecordId string Item record id used as the active spell id.
--- @return boolean active True while at least one effect still has duration.
local function isCastOnUseStillActive(itemRecordId)
    for _, spell in pairs(types.Actor.activeSpells(self)) do
        if spell.id == itemRecordId then
            for _, effect in pairs(spell.effects) do
                if effect.durationLeft and effect.durationLeft > 0 then
                    return true
                end
            end
        end
    end
    return false
end

--- Removes any Cast on Use bonuses whose source effects have expired.
local function pollCastOnUseBonuses()
    for itemRecordId, entry in pairs(activeCastOnUseBonuses) do
        if not isCastOnUseStillActive(itemRecordId) then
            reverseCastOnUseEntry(itemRecordId, entry)
        end
    end
end



--- Applies Wit of Telvanni's Cast on Use bonuses for the selected enchanted item.
--- Each eligible self-targeting non-harmful effect resolves its final magnitude
--- through the framework enchantment calculation channel.
--- @param item GameObject Selected enchanted item.
local function TelvanniWitEnchant(item)
    if not hasWitOfTelvanni then return end
    if not item or not item:isValid() then return end

    local enchRecord = getEnchantmentRecord(item)
    if not enchRecord then return end
    if enchRecord.type ~= core.magic.ENCHANTMENT_TYPE.CastOnUse then return end
    if not enchRecord.effects then return end

    if activeCastOnUseBonuses[item.recordId] then
        reverseCastOnUseEntry(item.recordId, activeCastOnUseBonuses[item.recordId])
    end


    local bonuses       = {}
    local activeEffects = types.Actor.activeEffects(self)

    for _, effectParams in ipairs(enchRecord.effects) do
        if not isHarmful(effectParams.id) then
            if effectParams.range == core.magic.RANGE.Self then
                local baseMag = (effectParams.magnitudeMin + effectParams.magnitudeMax) / 2
                local finalMag = interfaces.ErnPerkFramework.resolveCalculation({
                    calculation = CALCULATION.ENCHANT_CAST_ON_USE_SELF_EFFECT_MAGNITUDE,
                    baseValue = baseMag,
                    min = 0,
                    actor = self,
                    source = self,
                    context = {
                        item = item,
                        enchantment = enchRecord,
                        effect = effectParams,
                    },
                })
                local bonus = math.floor(finalMag - baseMag)
                if bonus > 0 then
                    local dynKey   = FORTIFY_DYN[effectParams.id]
                    local restKey  = RESTORE_DYN[effectParams.id]
                    local extraParam = effectParams.affectedAttribute
                                    or effectParams.affectedSkill
                                    or nil

                    if FORTIFY_ATTR[effectParams.id] and extraParam then
                        applyFortifyAttr(extraParam, bonus)
                        bonuses[#bonuses + 1] = {
                            id = effectParams.id, extraParam = extraParam,
                            bonus = bonus, path = "fortifyAttr",
                        }
                    elseif FORTIFY_SKILL[effectParams.id] and extraParam then
                        applyFortifySkill(extraParam, bonus)
                        bonuses[#bonuses + 1] = {
                            id = effectParams.id, extraParam = extraParam,
                            bonus = bonus, path = "fortifySkill",
                        }
                    elseif dynKey then
                        applyFortifyDyn(dynKey, bonus)
                        bonuses[#bonuses + 1] = {
                            id = effectParams.id, dynKey = dynKey,
                            bonus = bonus, path = "fortifyDyn",
                        }
                    elseif restKey then
                        applyRestoreDyn(restKey, bonus, effectParams.duration)
                        -- Instant lump sum - not tracked, no cleanup needed
                    else
                        if extraParam then
                            activeEffects:modify(bonus, effectParams.id, extraParam)
                        else
                            activeEffects:modify(bonus, effectParams.id)
                        end
                        bonuses[#bonuses + 1] = {
                            id = effectParams.id, extraParam = extraParam,
                            bonus = bonus, path = "modify",
                        }
                    end
                end
            end
        end
    end

    if #bonuses == 0 then return end

    activeCastOnUseBonuses[item.recordId] = { bonuses = bonuses }
    ui.showMessage("You Honour the Wit of House Telvanni.")
    utils.debug(2, "HT", "Wit applied CastOnUse bonus for " .. tostring(item.recordId))
end

-- ============================================================
--  ENCHANT SKILL HANDLER
-- ============================================================

interfaces.ErnPerkFramework.registerSkillUseHandler({
    id = "FactionPerks_telvanni_wit_enchant_use",
    skill = "enchant",
    priority = 200,
}, function(event)
    if not hasWitOfTelvanni  then return end
    local item = event.enchantedItem or types.Actor.getSelectedEnchantedItem(self)
    if not item then return end
    TelvanniWitEnchant(item)
end)

-- ============================================================
--  CONSTANT EFFECT
-- ============================================================

local EQUIPMENT_SLOTS = {
    types.Actor.EQUIPMENT_SLOT.Helmet,
    types.Actor.EQUIPMENT_SLOT.Cuirass,
    types.Actor.EQUIPMENT_SLOT.Greaves,
    types.Actor.EQUIPMENT_SLOT.LeftPauldron,
    types.Actor.EQUIPMENT_SLOT.RightPauldron,
    types.Actor.EQUIPMENT_SLOT.LeftGauntlet,
    types.Actor.EQUIPMENT_SLOT.RightGauntlet,
    types.Actor.EQUIPMENT_SLOT.Boots,
    types.Actor.EQUIPMENT_SLOT.Shirt,
    types.Actor.EQUIPMENT_SLOT.Pants,
    types.Actor.EQUIPMENT_SLOT.Skirt,
    types.Actor.EQUIPMENT_SLOT.Robe,
    types.Actor.EQUIPMENT_SLOT.LeftRing,
    types.Actor.EQUIPMENT_SLOT.RightRing,
    types.Actor.EQUIPMENT_SLOT.Amulet,
    types.Actor.EQUIPMENT_SLOT.Belt,
    types.Actor.EQUIPMENT_SLOT.CarriedRight,
    types.Actor.EQUIPMENT_SLOT.CarriedLeft,
}

--- Reverses a tracked Constant Effect equipment bonus.
--- @param boost table Saved boost data for one equipment slot.
local function reverseConstantBoost(boost)
    local activeEffects = types.Actor.activeEffects(self)
    for _, b in ipairs(boost.bonuses) do
        if b.path == "fortifyAttr" then
            applyFortifyAttr(b.extraParam, -b.bonus)
        elseif b.path == "fortifySkill" then
            applyFortifySkill(b.extraParam, -b.bonus)
        elseif b.path == "fortifyDyn" then
            applyFortifyDyn(b.dynKey, -b.bonus)
        else
            if b.extraParam then
                activeEffects:modify(-b.bonus, b.id, b.extraParam)
            else
                activeEffects:modify(-b.bonus, b.id)
            end
        end
    end
    utils.debug(2, "HT", "Wit reversed CE boost for item " .. tostring(boost.itemId))
end

--- Applies Wit of Telvanni's Constant Effect bonuses for one equipped item.
--- Each eligible non-harmful effect resolves its final magnitude through the
--- framework enchantment calculation channel before the extra delta is applied.
--- @param slot number Equipment slot id.
--- @param item GameObject Equipped item object.
--- @param enchRecord table Enchantment record.
local function applyConstantBoost(slot, item, enchRecord)
    local bonuses       = {}
    local activeEffects = types.Actor.activeEffects(self)

    for _, effectParams in ipairs(enchRecord.effects) do
        if not isHarmful(effectParams.id) then
            local baseMag    = (effectParams.magnitudeMin + effectParams.magnitudeMax) / 2
            local finalMag = interfaces.ErnPerkFramework.resolveCalculation({
                calculation = CALCULATION.ENCHANT_CONSTANT_EFFECT_SELF_EFFECT_MAGNITUDE,
                baseValue = baseMag,
                min = 0,
                actor = self,
                source = self,
                context = {
                    slot = slot,
                    item = item,
                    enchantment = enchRecord,
                    effect = effectParams,
                },
            })
            local bonus = math.floor(finalMag - baseMag)
            if bonus > 0 then
                local extraParam = effectParams.affectedAttribute
                               or effectParams.affectedSkill
                               or nil
                local dynKey = FORTIFY_DYN[effectParams.id]

                if FORTIFY_ATTR[effectParams.id] and extraParam then
                    applyFortifyAttr(extraParam, bonus)
                    bonuses[#bonuses + 1] = {
                        id = effectParams.id, extraParam = extraParam,
                        bonus = bonus, path = "fortifyAttr",
                    }
                elseif FORTIFY_SKILL[effectParams.id] and extraParam then
                    applyFortifySkill(extraParam, bonus)
                    bonuses[#bonuses + 1] = {
                        id = effectParams.id, extraParam = extraParam,
                        bonus = bonus, path = "fortifySkill",
                    }
                elseif dynKey then
                    applyFortifyDyn(dynKey, bonus)
                    bonuses[#bonuses + 1] = {
                        id = effectParams.id, dynKey = dynKey,
                        bonus = bonus, path = "fortifyDyn",
                    }
                else
                    if extraParam then
                        activeEffects:modify(bonus, effectParams.id, extraParam)
                    else
                        activeEffects:modify(bonus, effectParams.id)
                    end
                    bonuses[#bonuses + 1] = {
                        id = effectParams.id, extraParam = extraParam,
                        bonus = bonus, path = "modify",
                    }
                end
            end
        end
    end

    if #bonuses > 0 then
        activeConstantBoosts[slot] = { itemId = item.id, bonuses = bonuses }
        utils.debug(2, "HT", "Wit applied CE boost for slot " .. tostring(slot))
    end
end

--- Reverses and clears every tracked Constant Effect equipment bonus.
local function removeAllConstantBoosts()
    for slot, boost in pairs(activeConstantBoosts) do
        reverseConstantBoost(boost)
    end
    activeConstantBoosts = {}
end

--- Reconciles equipped Constant Effect items with the active boost table.
--- Called periodically and on cell changes to catch equipment swaps and scaling changes.
local function updateConstantEffects()
    if not hasWitOfTelvanni then return end

    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local item    = types.Actor.getEquipment(self, slot)
        local current = activeConstantBoosts[slot]

        local currentItemId = (item and item:isValid()) and item.id or nil
        local boostedItemId = current and current.itemId or nil

        if currentItemId ~= boostedItemId then
            if current then
                reverseConstantBoost(current)
                activeConstantBoosts[slot] = nil
            end
            if item and item:isValid() then
                local enchRecord = getEnchantmentRecord(item)
                if enchRecord and
                   enchRecord.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
                    applyConstantBoost(slot, item, enchRecord)
                end
            end
        end
    end
end

-- ============================================================
--  HOUSE TELVANNI PERKS
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = ht1_id,
    localizedName = "Uninvited Student",
    category = {"FactionPerks", "Great Houses", "House Telvanni", 1},
    localizedFlavour = "House Telvanni does not recruit - it tolerates those strong enough to push "
        .. "their way in. You have done so. For now, that is enough.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+3 Intelligence, +3 Willpower, "
        .. "+5 Enchant, +5 Conjuration)\f"
        .. "Effect 2: \n Grants Bound Helm and Bound Cuirass.\f"
        .. "Effect 3: \n Wit of Telvanni: Cast on Use enchantments targeting yourself are augmented "
        .. "based on Telvanni reputation. At reputation cap: +150% effect magnitude. "
        .. "Constant Effect enchantments on equipped items are permanently augmented. "
        .. "At reputation cap: +100% effect magnitude. Harmful effects are never boosted.",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("telvanni",0),
        R.minimumLevel(1),
    },
    onAdd = function()
        setRank(1)
        reportAAM()
        safeAddSpell("bound helm")
        safeAddSpell("bound cuirass")
        hasWitOfTelvanni = true
        -- Tables restored from save by onLoad - just run CE detection
        updateConstantEffects()
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("bound helm")
        safeRemoveSpell("bound cuirass")
        hasWitOfTelvanni     = false
        lastHTCellId         = nil
        for itemRecordId, entry in pairs(activeCastOnUseBonuses) do
            reverseCastOnUseEntry(itemRecordId, entry)
        end
        removeAllConstantBoosts()
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = ht2_id,
    localizedName = "Tower Sorcery",
    category = {"FactionPerks", "Great Houses", "House Telvanni", 2},
    localizedFlavour = "Telvanni wizards are defined by their mastery of enchantment. "
        .. "You have begun to understand the principles that animate their towers and servants.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+5 Intelligence, +5 Willpower, "
        .. "+10 Enchant, +10 Conjuration)\f"
        .. "Effect 2: \n Grants Tranasa's Spelltrap.",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R.hasPerk(ht1_id),
        FactionGroupRank("telvanni",3),
        R.minimumAttributeLevel('intelligence', 40),
        R.minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        reportAAM()
        safeAddSpell("tranasa's spelltrap")
    end,
    onRemove = function()
        setRank(nil)
        reportAAM()
        safeRemoveSpell("tranasa's spelltrap")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = ht3_id,
    localizedName = "Self-Made Power",
    category = {"FactionPerks", "Great Houses", "House Telvanni", 3},
    persistentSpells = function()
        return getHTRank() == 3 and { "FPerks_HT3_Restore_Magicka_1" } or {}
    end,
    localizedFlavour = "House Telvanni respects only power earned, never granted. "
        .. "You have shaped yourself through relentless study.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+10 Intelligence, +10 Willpower, "
        .. "+18 Enchant, +18 Conjuration)\f"
        .. "Effect 2: \n Fortify Maximum Magicka by 0.5x Intelligence. Restore Magicka 1pt/s.",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R.hasPerk(ht2_id),
        FactionGroupRank("telvanni",6),
        R.minimumAttributeLevel('intelligence', 50),
        R.minimumLevel(10),
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
    id = ht4_id,
    localizedName = "Telvanni Lord",
    category = {"FactionPerks", "Great Houses", "House Telvanni", 4},
    persistentSpells = function()
        return getHTRank() == 4 and { "FPerks_HT4_Restore_Magicka_2" } or {}
    end,
    localizedFlavour = "You are acknowledged by the Telvanni masters - a rare concession from those "
        .. "who acknowledge no one. The heights are yours to claim.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Intelligence, +15 Willpower, "
        .. "+25 Enchant, +25 Conjuration)\f"
        .. "Effect 2: \n Fortify Maximum Magicka by 1.0x Intelligence. "
        .. "Restore Magicka 2pt/s.",
    hidden = utils.leaderTrainingHidden("telvanni", perkHidden(GUILD, 9, 15)),
    art = "textures\\levelup\\mage",
    cost = function() return utils.leaderTrainingPerkCost(4) end,
    requirements = utils.leaderTrainingPerkRequirements("telvanni", 9, {
        R.hasPerk(ht3_id),
        FactionGroupRank("telvanni",9),
        R.minimumAttributeLevel('intelligence', 75),
        R.minimumLevel(15),
    }),
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

--- Polls Cast on Use expirations and reconciles Constant Effect equipment boosts.
--- @param dt number Frame delta time.
local function onUpdate(dt)
    if not hasWitOfTelvanni then return end

    -- Poll CastOnUse bonuses for expiry via durationLeft
    castOnUsePollTimer = castOnUsePollTimer - dt
    if castOnUsePollTimer <= 0 then
        castOnUsePollTimer = CAST_ON_USE_POLL_INTERVAL
        pollCastOnUseBonuses()
    end

    -- Cell change: recalculate CE scale
    local cell   = self.cell
    local cellId = cell and cell.id or nil
    if cellId ~= lastHTCellId then
        lastHTCellId = cellId
        removeAllConstantBoosts()
        updateConstantEffects()
    end

    -- Periodic equipment change check
    equipmentCheckTimer = equipmentCheckTimer - dt
    if equipmentCheckTimer <= 0 then
        equipmentCheckTimer = EQUIPMENT_CHECK_INTERVAL
        updateConstantEffects()
    end
end

--- Persists active Telvanni bonus tracking and stat modifiers.
--- @return table state Save payload.
local function onSave()
    return {
        activeCastOnUseBonuses = activeCastOnUseBonuses,
        activeConstantBoosts   = activeConstantBoosts,
        appliedStats = appliedStats
    }
end

--- Restores Telvanni tracking tables and clears saved stat deltas before reapplication.
--- @param data table|nil Save payload.
local function onLoad(data)
    data = data or {}
    -- Restore tracking tables only - bonuses already baked into
    -- stat.modifier from the save file, so nothing is re-applied.
    activeCastOnUseBonuses = data.activeCastOnUseBonuses or {}
    activeConstantBoosts   = data.activeConstantBoosts   or {}
    utils.clearSavedAppliedStats(data.appliedStats, appliedStats)
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onSave   = onSave,
        onLoad   = onLoad,
    },
}
