local interfaces = require("openmw.interfaces")
local types = require('openmw.types')
local self = require('openmw.self')
local core = require('openmw.core')

--- Returns the actor-local framework interface after it has attached.
--- Actor scripts can start before sibling local-script interfaces are visible,
--- so framework lookups must happen inside handlers, not at module load.
local function framework()
    return interfaces.ErnPerkFramework
end
-- ============================================================
-- MORAG TONG SNEAK ATTACKS
-- ============================================================

FPerks_PlayerIsSneaking = false

--- Receives the player's current sneak state for Morag Tong target scripts.
--- @param currentSneakStatus boolean Whether the player is currently sneaking.
function FPerks_UpdatePlayerSneakStatus(currentSneakStatus)
    FPerks_PlayerIsSneaking = currentSneakStatus
end

--- Checks whether a target-side Morag Tong lifesteal hit qualifies.
--- @param attack table OpenMW combat attack table.
--- @return boolean successful True when the player was sneaking for this hit.
local function MT4AttackSuccessful(attack)
    -- Player must be sneaking at the moment of the hit
    if not FPerks_PlayerIsSneaking then --If FPerks_PlayerIsSneaking is false, back out
        return false
    end

    --Proceed

    return true --If all checks pass, the attack qualifies for lifesteal
end

--- Applies Morag Tong lifesteal to this target when the hit qualifies.
--- @param attack table OpenMW combat attack table.
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
-- Called from actor.lua hit handlers.
-- ============================================================

local lastICSmiteTime = nil  -- per-instance cooldown; each NPC/creature has its own Lua state

local IC_SMITE_CREATURE_TYPES = {
    [types.Creature.TYPE.Undead] = true,
    [types.Creature.TYPE.Daedra] = true,
}

--- Classifies actors eligible for Imperial Cult Divine Smite.
--- @param actor GameObject Actor object to test.
--- @return boolean eligible True for undead, daedra, or vampire actors.
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

--- Applies Imperial Cult Divine Smite to this target after player-side checks.
--- The flat damage is resolved through `direct.damage.health` before being
--- written to health, allowing other mods to affect direct damage consistently.
--- @param package table Tuple: attack, faction rank, smite level.
function FPerks_DoICSmite(package)
    local attack = package[1]
    local rank = package[2]
    local smiteLevel = package[3]
    
    -- Checks player is eligible to Smite
    if smiteLevel < 3 then 
        return
    end

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
    local fw = framework()
    if fw == nil then
        return
    end

    local dmg = fw.applyActorResourceDelta({
        actor = self,
        resource = "health",
        operation = fw.RESOURCE_OPERATION.Damage,
        amount = rank * 10,
        source = attack.attacker,
        sourceEffect = "FactionPerks_IC_Smite",
        damageType = "divine",
        context = {
            sourceEffect = "FactionPerks_IC_Smite",
            damageType = "divine",
            attack = attack,
            rank = rank,
            smiteLevel = smiteLevel,
        },
    })

    attack.successful = true

    lastICSmiteTime = now
    attack.attacker:sendEvent("FPerks_IC_SmiteProc", { dmg = dmg })
end
