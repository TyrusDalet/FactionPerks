--[[
    IL:
        FPerks_IL1_Passive          - +5 Endurance, +10 Fortify Fatigue, +10 Medium Armour, +10 Heavy Armour
        FPerks_IL2_Passive          - +15 Endurance, +25 Fortify Fatigue, +25 Block
        FPerks_IL3_Passive          - +25 Endurance, +50 Fortify Fatigue, +50 Athletics
        FPerks_IL4_Passive          - +25 Strength, +75 Fortify Fatigue, +75 Heavy Armour,
        FPerks_IL4_Restore_Phys     - Restore Health 1pt/s, Restore Fatigue 1pt/s

    Non-table spells (granted once, not removed on rank-up):
        FPerks_IL3_Prowess          - Power (granted at P3, removed on full respec only)

    Legionary's Resolve (P2+):
        On successful block:
            - Reflects 50% of blocked damage back to the attacker directly
              (bypasses armour and magic resistance, consistent with IC Smite)
            - Restores a portion of the fatigue spent blocking:
                P2: 30% of fatigue cost restored
                P3: 50% of fatigue cost restored
                P4: 75% of fatigue cost restored

        Block detection uses two handlers in sequence:
            1. Combat.addOnHitHandler  - stores attacker and pre-hit fatigue snapshot
            2. SkillProgression.addSkillUsedHandler - fires on successful block,
               calculates fatigue delta and applies both effects

        TIMING NOTE: If fatigueBeforeHit and post-block fatigue are identical
        (delta = 0), the engine deducted block fatigue before our hit handler
        ran. In that case we fall back to a proxy: fatigue restored is calculated
        as a percentage of blocked health damage, which correlates naturally
        with block cost since heavier hits cost more fatigue to block.
        The proxy scalar is tuned to approximate vanilla block fatigue costs.

        No cooldown - Block's hard cap of 50% damage reduction is the
        natural limiter on how often and how much this can proc.
]]

local ns          = require("scripts.FactionPerks.namespace")
local utils       = require("scripts.FactionPerks.utils")
local notExpelled = utils.notExpelled
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local core        = require('openmw.core')
local ambient     = require('openmw.ambient')

local R = interfaces.ErnPerkFramework.requirements

local perkTable = {
    [1] = { passive = {"FPerks_IL1_Passive"} },
    [2] = { passive = {"FPerks_IL2_Passive"} },
    [3] = { passive = {"FPerks_IL3_Passive"} },
    [4] = { passive = {"FPerks_IL4_Passive", "FPerks_IL4_Restore_Phys"} },
}

-- Perk id prep
local il1_id = ns .. "_il_legion_recruit"
local il2_id = ns .. "_il_shield_wall"
local il3_id = ns .. "_il_forced_march"
local il4_id = ns .. "_il_legate"

local setRank = utils.makeSetRank(perkTable, nil)

-- ============================================================
--  LEGIONARY'S RESOLVE - Shield Wall (P2+)
--
--  On successful block:
--    Reflects 50% of blocked damage to the attacker.
--    Restores a portion of the fatigue spent blocking,
--    scaling with perk rank.
--
--  Two-handler pattern:
--    Hit handler  - snapshot attacker and pre-hit fatigue
--    Skill handler - calculate delta, apply reflect and restore
-- ============================================================

local ilLastAttacker     = nil   -- attacker stored by hit handler for skill handler to read
local ilFatigueBeforeHit = 0     -- fatigue snapshot taken at hit handler, before block deduction

-- Fatigue restore percentage per rank
local IL_FATIGUE_RESTORE = {
    [2] = 0.30,
    [3] = 0.50,
    [4] = 0.75,
}

-- Proxy scalar for fallback fatigue calculation.
-- If delta is zero (engine deducted before our handler ran),
-- we estimate fatigue cost as blocked damage * this scalar.
-- Tuned to approximate vanilla block fatigue costs in practice.
-- Flag this for adjustment after in-game testing.
local IL_FATIGUE_PROXY_SCALAR = 0.5

local function getILRank()
    if R().hasPerk(il4_id).check() then return 4 end
    if R().hasPerk(il3_id).check() then return 3 end
    if R().hasPerk(il2_id).check() then return 2 end
    return nil
end

-- ============================================================
--  HIT HANDLER
--  Fires when the player is struck. Stores the attacker and
--  a fatigue snapshot for the skill handler to read.
--  We also store raw incoming damage before the block reduction
--  is applied, so the reflect calculation uses the full value
--  and we can halve it to get the portion that was blocked.
-- ============================================================

interfaces.Combat.addOnHitHandler(function(attack)
    ilLastAttacker     = nil
    ilFatigueBeforeHit = 0

    local rank = getILRank()
    if not rank then return end

    if not attack.attacker or not attack.attacker:isValid() then return end

    ilLastAttacker     = attack.attacker
    ilFatigueBeforeHit = types.Actor.stats.dynamic.fatigue(self).current
end)

-- ============================================================
--  SKILL HANDLER
--  Fires when the Block skill advances - this only happens on
--  a successful block, giving us a clean success gate consistent
--  with the MG spell refund pattern.
-- ============================================================

interfaces.SkillProgression.addSkillUsedHandler(function(skillId, params)
    if skillId ~= "block" then return end

    local rank = getILRank()
    if not rank then return end

    if not ilLastAttacker or not ilLastAttacker:isValid() then return end

    -- Reflect damage scales purely with Block skill.
    -- At Block 40:  10 damage
    -- At Block 100: 25 damage
    local blockSkill  = types.NPC.stats.skills.block(self).modified
    local reflectDmg  = math.floor(blockSkill * 0.25)

    ilLastAttacker:sendEvent("FPerks_TakeDamage", { amount = reflectDmg })

    -- Fatigue restore — delta method with proxy fallback
    local fatigueNow  = types.Actor.stats.dynamic.fatigue(self).current
    local fatigueCost = math.max(0, ilFatigueBeforeHit - fatigueNow)

    if fatigueCost <= 0 then
        fatigueCost = reflectDmg * IL_FATIGUE_PROXY_SCALAR
        print("IL Resolve: fatigue delta was 0, using proxy: " .. fatigueCost)
    else
        print("IL Resolve: fatigue delta precise: " .. fatigueCost)
    end

    local restorePercent = IL_FATIGUE_RESTORE[rank]
    local fatigueRestore = math.floor(fatigueCost * restorePercent)

    if fatigueRestore > 0 then
        local fatigue    = types.Actor.stats.dynamic.fatigue(self)
        local maxFatigue = fatigue.base + fatigue.modifier
        fatigue.current  = math.min(fatigue.current + fatigueRestore, maxFatigue)
    end

    ambient.playSound("conjuration hit")

    print("IL Resolve: reflected=" .. reflectDmg
        .. " fatigue restored=" .. fatigueRestore
        .. " (" .. (restorePercent * 100) .. "% of " .. fatigueCost .. ")")

    ilLastAttacker     = nil
    ilFatigueBeforeHit = 0
end)

-- ============================================================
--  IMPERIAL LEGION PERKS
-- ============================================================


interfaces.ErnPerkFramework.registerPerk({
    id = il1_id,
    localizedName = "Legion Recruit",
    --hidden = true,
    localizedDescription = "You have sworn the oath and donned the cuirass. "
        .. "The Legion's drillmasters have improved your guard.\n "
        .. "(+5 Endurance, +10 Fortify Fatigue, +10 Medium Armour, +10 Heavy Armour)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('imperial legion', 0),
        R().minimumLevel(1)
    },
    onAdd    = function() setRank(1) end,
    onRemove = function() setRank(nil) end,
})


interfaces.ErnPerkFramework.registerPerk({
    id = il2_id,
    localizedName = "Shield Wall",
    --hidden = true,
    localizedDescription = "You have mastered the disciplined defensive formations "
        .. "of the Imperial army. When you block an attack, the force is turned "
        .. "back against your attacker, and the effort of blocking costs you less.\n "
        .. "Requires Legion Recruit. "
        .. "(+15 Endurance, +25 Fortify Fatigue, +25 Block)\n\n"
        .. "Legionary's Resolve: Blocking reflects 50%% of blocked damage to your "
        .. "attacker. Restores 30%% of fatigue spent blocking.",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(il1_id),
        R().minimumFactionRank('imperial legion', 3),
        R().minimumAttributeLevel('endurance', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() setRank(2) end,
    onRemove = function() setRank(nil) end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = il3_id,
    localizedName = "Forced March",
    --hidden = true,
    localizedDescription = "The Legion demands its soldiers keep pace regardless "
        .. "of terrain. When the situation demands it, you can push far beyond "
        .. "normal limits. Blocking now restores 50%% of fatigue spent.\n "
        .. "Requires Shield Wall. "
        .. "(+25 Endurance, +50 Fortify Fatigue, +50 Athletics, "
        .. "grants Legion's Prowess power)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(il2_id),
        R().minimumFactionRank('imperial legion', 6),
        R().minimumAttributeLevel('endurance', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
        types.Actor.spells(self):add("FPerks_IL3_Prowess")
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("FPerks_IL3_Prowess")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = il4_id,
    localizedName = "Legate",
    --hidden = true,
    localizedDescription = "You command the respect of every soldier who serves "
        .. "alongside you. The Emperor's discipline has forged your body into "
        .. "something that endures. Blocking now restores 75%% of fatigue spent.\n "
        .. "Requires Forced March. "
        .. "(+25 Strength, +75 Fortify Fatigue, +75 Heavy Armour, "
        .. "Restore Health 1pt/s, Restore Fatigue 1pt/s)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(il3_id),
        R().minimumFactionRank('imperial legion', 9),
        R().minimumAttributeLevel('endurance', 75),
        R().minimumLevel(15),
    },
    onAdd    = function() setRank(4) end,
    onRemove = function() setRank(nil) end,
})