--[[
    HT:
        FPerks_HT1_Passive          - +3 Intelligence, +3 Willpower,
                                      +5 Enchant, +5 Conjuration
        FPerks_HT2_Passive          - +5 Intelligence, +5 Willpower,
                                      +10 Enchant, +10 Conjuration
        FPerks_HT3_Passive          - +10 Intelligence, +10 Willpower,
                                      +18 Enchant, +18 Conjuration
        FPerks_HT4_Passive          - +15 Intelligence, +15 Willpower,
                                      +25 Enchant, +25 Conjuration

    Honour The Great House (P1+): Wit of the Telvanni

        CAST ON USE:
        When the player activates a Cast on Use enchanted item, self-range
        effects are augmented via activeEffects:modify + cleanup timer.
        Touch and Target range effects are excluded - activeEffects:modify
        only affects the player, and reliable post-hoc modification of
        target actors is not feasible from a player script.
        Scale: honourScale * 1.5, capped behaviour per honourScale post-cap.
        At rep cap: +150% bonus magnitude (250% total).
        Detection: SkillProgression enchant handler confirms success,
        reads getSelectedEnchantedItem directly since Cast on Use uses
        the unequip animation group rather than spellcast.

        CONSTANT EFFECT:
        All equipped items with Constant Effect enchantments have their
        effects augmented via activeEffects:modify. Tracked per equipment
        slot - when items are equipped or unequipped, bonuses are reversed
        and reapplied accordingly.
        Scale: math.min(honourScale, 1.0), giving at most +100% bonus
        magnitude (200% total), slightly less powerful than CastOnUse
        since the effect is permanent.
        Bonus updates when equipment changes, and is also recalculated
        on cell change so faction reputation gains are reflected without
        needing to re-equip.
]]

local ns          = require("scripts.FactionPerks.namespace")
local utils       = require("scripts.FactionPerks.utils")
local perkHidden  = utils.perkHidden
local GUILD        = utils.FACTION_GROUPS.telvanni
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
--  WIT OF THE TELVANNI - shared state
-- ============================================================

local hasWitOfTelvanni   = false
local currentEnchantedItem = nil  -- cached by skill handler for CastOnUse path

-- ============================================================
--  EFFECT CLASSIFICATION TABLES
--  Used by both CastOnUse and Constant Effect paths.
-- ============================================================

local FORTIFY_ATTR  = { ["fortifyattribute"] = true }
local FORTIFY_SKILL = { ["fortifyskill"]     = true }
local RESTORE_DYN   = {
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
    if total == 0 then return end
    local dyn = types.Actor.stats.dynamic[dynKey]
    if dyn then
        local s = dyn(self)
        s.current = math.min(s.current + total, s.base + s.modifier)
    end
end

-- ============================================================
--  SHARED ENCHANTMENT RECORD READER
--  Iterates item types to find an enchantment record on any
--  equippable item type. Used by both CastOnUse and Constant
--  Effect paths.
-- ============================================================

local ENCHANTABLE_TYPES = {
    types.Weapon,
    types.Armor,
    types.Clothing,
    types.Miscellaneous,
    types.Book,
}

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

-- ============================================================
--  CAST ON USE - Wit of the Telvanni
--
--  When the player activates a Cast on Use enchanted item,
--  ALL effects regardless of range are augmented. This means
--  both self-targeting and enemy-targeting effects benefit,
--  making offensive enchanted items worth using.
--
--  Detection: SkillProgression enchant handler fires on success.
--  getSelectedEnchantedItem is read directly here since Cast
--  on Use uses the unequip animation, not the spellcast group.
--
--  Scale: honourScale * 1.5 (max +150%, total 250%).
--  Cleanup: async timers reverse each bonus after its duration.
-- ============================================================

local function TelvanniWitEnchant(item)
    if not hasWitOfTelvanni then return end
    if not item or not item:isValid() then return end

    local enchRecord = getEnchantmentRecord(item)
    if not enchRecord then return end
    if enchRecord.type ~= core.magic.ENCHANTMENT_TYPE.CastOnUse then return end
    if not enchRecord.effects then return end

    local scale = utils.honourScale('telvanni') * 1.5
    if scale <= 0 then return end

    -- Build bonus list from self-range effects only.
    -- Touch and Target effects cannot be reliably augmented on
    -- the target actor from a player script, so are excluded.
    -- The Telvanni wit reflects inward - self-mastery and
    -- self-enhancement are the hallmark of their craft.
    local bonuses = {}
    for _, effectParams in ipairs(enchRecord.effects) do
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
                -- Attribute fortification: use stat modifier path for clean reversal
                applyFortifyAttr(b.extraParam, b.bonus)
                async:newUnsavableSimulationTimer(b.duration - timer, function()
                    applyFortifyAttr(b.extraParam, -b.bonus)
                end)
            elseif FORTIFY_SKILL[b.id] and b.extraParam then
                -- Skill fortification: use stat modifier path for clean reversal
                applyFortifySkill(b.extraParam, b.bonus)
                async:newUnsavableSimulationTimer(b.duration - timer, function()
                    applyFortifySkill(b.extraParam, -b.bonus)
                end)
            elseif dynKey then
                -- Restore effects: apply as instant lump sum, no reversal needed
                applyRestoreDyn(dynKey, b.bonus, b.duration)
            else
                -- Everything else: activeEffects:modify with cleanup timer
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
        ui.showMessage("You Honour the Wit of House Telvanni.")
    end)
end

-- ============================================================
--  ENCHANT SKILL HANDLER
--  Fires only on successful Cast on Use activation since the
--  Enchant skill only advances on success. Reads the selected
--  enchanted item directly rather than caching from animation,
--  since Cast on Use uses the unequip animation group.
-- ============================================================

interfaces.SkillProgression.addSkillUsedHandler(function(skillId, params)
    if skillId ~= "enchant"  then return end
    if not hasWitOfTelvanni  then return end

    local item = types.Actor.getSelectedEnchantedItem(self)
    if not item then return end

    TelvanniWitEnchant(item)
end)

-- ============================================================
--  CONSTANT EFFECT - Wit of the Telvanni
--
--  Scans all equipment slots on a timer and on cell change.
--  When a Constant Effect enchanted item is found, augments
--  its effects via activeEffects:modify. Tracked per slot so
--  bonuses are reversed cleanly when items change.
--
--  Cell change triggers a full recalculation so faction
--  reputation gains are reflected without re-equipping.
--
--  Scale: math.min(honourScale, 1.0) (max +100%, total 200%).
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

-- Keyed by slot number. Each entry: { itemId, bonuses = {{id, extraParam, bonus}...} }
local activeConstantBoosts    = {}
local equipmentCheckTimer     = 0
local EQUIPMENT_CHECK_INTERVAL = 2.0
local lastHTCellId            = nil  -- tracks cell changes for scale recalculation

local function reverseConstantBoost(boost)
    -- Each bonus stores its path so reversal uses the same route as application.
    -- fortifyAttr and fortifySkill used the stat modifier path directly -
    -- activeEffects:modify doesn't update those values for constant effects.
    -- Everything else used activeEffects:modify and is reversed the same way.
    local activeEffects = types.Actor.activeEffects(self)
    for _, b in ipairs(boost.bonuses) do
        if b.path == "fortifyAttr" then
            applyFortifyAttr(b.extraParam, -b.bonus)
        elseif b.path == "fortifySkill" then
            applyFortifySkill(b.extraParam, -b.bonus)
        else
            if b.extraParam then
                activeEffects:modify(-b.bonus, b.id, b.extraParam)
            else
                activeEffects:modify(-b.bonus, b.id)
            end
        end
    end
    print("HT Wit: Reversed constant boost for item " .. tostring(boost.itemId))
end

local function applyConstantBoost(slot, item, enchRecord)
    -- Scale capped at 1.0 for constant effects (200% total, less than CastOnUse's 250%)
    local scale = math.min(utils.honourScale('telvanni'), 1.0)
    if scale <= 0 then return end

    local bonuses       = {}
    local activeEffects = types.Actor.activeEffects(self)

    for _, effectParams in ipairs(enchRecord.effects) do
        local baseMag    = (effectParams.magnitudeMin + effectParams.magnitudeMax) / 2
        local bonus      = math.floor(baseMag * scale)
        if bonus > 0 then
            local extraParam = effectParams.affectedAttribute
                           or effectParams.affectedSkill
                           or nil

            -- Fortify Attribute and Fortify Skill effects are managed by
            -- the engine at application time - activeEffects:modify has no
            -- effect on them for constant effects. Write directly to the
            -- stat modifier instead, same as the CastOnUse path.
            if FORTIFY_ATTR[effectParams.id] and extraParam then
                applyFortifyAttr(extraParam, bonus)
                bonuses[#bonuses + 1] = {
                    id         = effectParams.id,
                    extraParam = extraParam,
                    bonus      = bonus,
                    path       = "fortifyAttr",
                }
            elseif FORTIFY_SKILL[effectParams.id] and extraParam then
                applyFortifySkill(extraParam, bonus)
                bonuses[#bonuses + 1] = {
                    id         = effectParams.id,
                    extraParam = extraParam,
                    bonus      = bonus,
                    path       = "fortifySkill",
                }
            else
                -- Everything else: activeEffects:modify works correctly
                -- for constant effects that the engine reads each frame
                -- (Chameleon, Night Eye, resistances, etc.)
                if extraParam then
                    activeEffects:modify(bonus, effectParams.id, extraParam)
                else
                    activeEffects:modify(bonus, effectParams.id)
                end
                bonuses[#bonuses + 1] = {
                    id         = effectParams.id,
                    extraParam = extraParam,
                    bonus      = bonus,
                    path       = "modify",
                }
            end
        end
    end

    if #bonuses > 0 then
        activeConstantBoosts[slot] = {
            itemId  = item.id,
            bonuses = bonuses,
        }
        print("HT Wit: Applied constant boost for slot " .. tostring(slot))
    end
end

local function removeAllConstantBoosts()
    for slot, boost in pairs(activeConstantBoosts) do
        reverseConstantBoost(boost)
    end
    activeConstantBoosts = {}
end

local function updateConstantEffects()
    if not hasWitOfTelvanni then return end

    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local item    = types.Actor.getEquipment(self, slot)
        local current = activeConstantBoosts[slot]

        local currentItemId = (item and item:isValid()) and item.id or nil
        local boostedItemId = current and current.itemId or nil

        if currentItemId ~= boostedItemId then
            -- Slot contents changed - reverse old boost if any
            if current then
                reverseConstantBoost(current)
                activeConstantBoosts[slot] = nil
            end

            -- Apply new boost if item has a constant effect enchantment
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

local ht1_id = ns .. "_ht_uninvited_student"
interfaces.ErnPerkFramework.registerPerk({
    id = ht1_id,
    localizedName = "Uninvited Student",
    localizedDescription = "House Telvanni does not recruit - it tolerates those strong "
        .. "enough to push their way in. You have done so. For now, that is enough.\
 "
        .. "(+3 Intelligence, +3 Willpower, +5 Enchant, +5 Conjuration, "
        .. "grants Bound Helm and Cuirass)\
\
"
        .. "Honour the Wit of the Great House Telvanni: Cast on Use enchantments "
        .. "that target yourself are augmented based on your Telvanni reputation. "
        .. "At reputation cap: effects are 250%% of their base magnitude.\
"
        .. "Constant Effect enchantments on equipped items are permanently "
        .. "augmented. At reputation cap: effects are 200%% of their base magnitude.",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('telvanni', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        setRank(1)
        types.Actor.spells(self):add("bound helm")
        types.Actor.spells(self):add("bound cuirass")

        hasWitOfTelvanni = true
        -- Apply constant effect boosts immediately for currently equipped items
        updateConstantEffects()
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("bound helm")
        types.Actor.spells(self):remove("bound cuirass")
        hasWitOfTelvanni     = false
        currentEnchantedItem = nil
        lastHTCellId         = nil
        -- Reverse all constant effect boosts cleanly
        removeAllConstantBoosts()
    end,
})

local ht2_id = ns .. "_ht_tower_sorcery"
interfaces.ErnPerkFramework.registerPerk({
    id = ht2_id,
    localizedName = "Tower Sorcery",
    localizedDescription = "Telvanni wizards are defined by their mastery of enchantment. "
        .. "You have begun to understand the principles that animate their towers "
        .. "and servants.\
 "
        .. "Requires Uninvited Student. "
        .. "(+5 Intelligence, +5 Willpower, +10 Enchant, +10 Conjuration, "
        .. "grants Tranasa's Spelltrap)",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(ht1_id),
        R().minimumFactionRank('telvanni', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        types.Actor.spells(self):add("tranasa's spelltrap")
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("tranasa's spelltrap")
    end,
})

local ht3_id = ns .. "_ht_self_made_power"
interfaces.ErnPerkFramework.registerPerk({
    id = ht3_id,
    localizedName = "Self-Made Power",
    localizedDescription = "House Telvanni respects only power earned, never granted. "
        .. "You have shaped yourself through relentless study.\
 "
        .. "Requires Tower Sorcery. "
        .. "(+10 Intelligence, +10 Willpower, +18 Enchant, +18 Conjuration)",
    hidden = perkHidden(GUILD, 6, 10),
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
    localizedDescription = "You are acknowledged by the Telvanni masters - a rare "
        .. "concession from those who acknowledge no one. The heights are yours "
        .. "to claim.\
 "
        .. "Requires Self-Made Power. "
        .. "(+15 Intelligence, +15 Willpower, +25 Enchant, +25 Conjuration)",
    hidden = perkHidden(GUILD, 9, 15),
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(ht3_id),
        R().minimumFactionRank('telvanni', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd    = function() setRank(4) end,
    onRemove = function() setRank(nil) end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================

local function onUpdate(dt)
    if not hasWitOfTelvanni then return end

    -- Cell change check: recalculate constant effect scale when the
    -- player moves to a new cell. This reflects faction reputation
    -- gains without requiring re-equipping. Clears the boost cache
    -- first so updateConstantEffects sees all slots as changed.
    local cell   = self.cell
    local cellId = cell and cell.id or nil
    if cellId ~= lastHTCellId then
        lastHTCellId = cellId
        removeAllConstantBoosts()
        updateConstantEffects()
    end

    -- Periodic equipment change check
    equipmentCheckTimer = equipmentCheckTimer - dt
    if equipmentCheckTimer == 0 then
        equipmentCheckTimer = EQUIPMENT_CHECK_INTERVAL
        updateConstantEffects()
    end
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
}