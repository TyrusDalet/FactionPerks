local ns = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types = require('openmw.types')
local self = require('openmw.self')
local core = require('openmw.core')
-- ============================================================
-- MORAG TONG SNEAK ATTACKS
-- ============================================================

local selfIsPlayer = self.type == types.Player
FPerks_PlayerIsSneaking = false

function FPerks_UpdatePlayerSneakStatus(currentSneakStatus)
    FPerks_PlayerIsSneaking = currentSneakStatus
end

local function MT4AttackSuccessful(attack)
    -- Player must be sneaking at the moment of the hit
    if not FPerks_PlayerIsSneaking then --If FPerks_PlayerIsSneaking is false, back out
        return false
    end

    --Proceed

    return true --If all checks pass, the attack qualifies for lifesteal
end

function FPerks_DoMT4Attack(attack)

    if not MT4AttackSuccessful(attack) then return end --If the attack wasn't successful, the modifier isn't applied

    -- if the blow did health damage, produce the magic effect
    if attack.damage.health > 0 then
        types.Actor.activeSpells(self):add({
        id = "FPerks_MT4_Lifesteal", -- Applies Mephala's Kiss
        effects = {0}, -- Applies effect 0; the Absorb Health effect

        --Sets caster to the player, so that the drain applies properly
        caster = attack.attacker,

        --Ignores all resistances and reflections to apply no matter what
        ignoreReflect = true,
        ignoreResistances = true,
        ignoreSpellAbsorption = true
        })

        -- message for debugging
        print("Mephala's Kiss Triggered!")

    else
        return
    end
end

-- ============================================================
-- IMPERIAL CULT SMITE
-- Active from P3. When the player strikes an undead, daedra,
-- or vampire with a weapon, divine damage is dealt directly
-- to the target's health, bypassing all resistances.
--
-- Damage = Imperial Cult faction rank x 10.
--   Minimum at P3 (rank 7): 70 damage.
--   Maximum at P4 (rank 10): 100 damage.
-- Per-target cooldown: 10s at P3, 5s at P4.
--
-- Perk presence is read directly from the player's spell list
-- via types.Actor.spells(attack.attacker) - readable from any
-- script context without needing cross-context flags.
-- Called from both npc.lua and creature.lua hit handlers.
-- ============================================================

local lastICSmiteTime = nil  -- per-instance cooldown; each NPC/creature has its own Lua state

local IC_SMITE_CREATURE_TYPES = {
    [types.Creature.TYPE.Undead] = true,
    [types.Creature.TYPE.Daedra] = true,
}

function FPerks_isSmiteTarget(actor)
    -- Undead and Daedra by creature type record
    if types.Creature.objectIsInstance(actor) then
        local ctype = types.Creature.record(actor).type
        if IC_SMITE_CREATURE_TYPES[ctype] then return true end
    end
    -- Vampires: any actor carrying the vampire attributes spell (NPC or creature)
    for _, spell in pairs(types.Actor.spells(actor)) do
        if spell.id == "vampire attributes" then return true end
    end
    return false
end

function FPerks_DoICSmite(package)
    print("Recieved Smite Information")
    local attack = package[1]
    local rank = package[2]
    local smiteLevel = package[3]
    
    -- Checks player is eligible to Smite
    if smiteLevel < 3 then 
    print("Not high enough rank in IC to Smite")
    return end

    local cooldown = 0

    if smiteLevel == 4 then cooldown = 5
    else cooldown = 10
    end

    local now = core.getSimulationTime()
    -- Fixed: was (now - lastICSmiteTime) == cooldown which almost never
    -- evaluates true on floating point; correct check is < cooldown
    if lastICSmiteTime and (now - lastICSmiteTime) < cooldown then return end

    -- Damage = faction rank x 10
    if not rank or rank == 0 then return end
    local dmg = rank * 10

    -- Apply divine damage directly, bypassing all magic systems
    local healthStat = types.Actor.stats.dynamic.health(self)
    attack.successful = true
    healthStat.current = healthStat.current - dmg

    lastICSmiteTime = now
    attack.attacker:sendEvent("FPerks_IC_SmiteProc", { dmg = dmg })

    print("IC Smite triggered! Damage: " .. tostring(dmg))
end