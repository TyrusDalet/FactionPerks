local ns         = "FactionPerks"
local pself      = require("openmw.self")
local types      = require("openmw.types")
local interfaces = require("openmw.interfaces")
local nearby     = require("openmw.nearby")

require("scripts.FactionPerks.shared")

local actorHitHandlerRegistered = false

--- Returns the actor-local framework interface after it has attached.
local function framework()
    return interfaces.ErnPerkFramework
end

-- ============================================================
--  TRIBUNAL TEMPLE TARGET CLASSIFICATION
--  Creature-only in practice. NPCs share this actor script, so all
--  creature-specific work is gated by object type.
-- ============================================================

local HONOURED_ANCESTORS = {
    ["ancestor ghost"] = true,
    ["bonelord"]       = true,
    ["bonewalker"]     = true,
}

--- Checks whether this actor is a Tribunal Temple calm target.
--- NPC contexts return false; only matching creature records qualify.
--- @return boolean match True for non-summoned handling candidates.
local function isHonouredAncestor()
    if not types.Creature.objectIsInstance(pself) then return false end
    local id = (types.Creature.record(pself).id or ""):lower()
    for name, _ in pairs(HONOURED_ANCESTORS) do
        if id:find(name, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- TRIBUNAL TEMPLE ENGINE HANDLERS
-- ============================================================

--- Handles creature activation for Honoured Ancestors.
--- Restores any stale calm modifier, excludes summons, and asks nearby players
--- whether their current perk state should calm this creature.
local function onActive()
    if not isHonouredAncestor() then return end

    -- Exclude summoned instances: summoned creatures have a Follow
    -- AI package pointing back to the player. We must not calm those
    -- as they are already allied.
    local following = false
    interfaces.AI.forEachPackage(function(param)
        if param.type == "Follow" then following = true end
    end)
    if following then return end

    -- Always restore fight modifier first. This ensures that if the
    -- player lost the perk while outside this cell, any previously
    -- applied calm modifier is cleared before we re-evaluate.
    types.Actor.stats.ai.fight(pself).modifier = 0

    -- Ping nearby players. Player script decides whether to calm.
    -- If the perk is held, the player will send _TT_CalmAncestor back.
    -- If not, the restore above is the final state.
    for _, player in ipairs(nearby.players) do
        player:sendEvent(ns .. "_TT_AncestorSpawned", { creature = pself })
    end
end

-- ============================================================
--  TRIBUNAL TEMPLE EVENT HANDLERS
-- ============================================================

--- Applies the reversible calm modifier used by Tribunal Temple perks.
--- @param data table|nil Unused event payload.
local function calmAncestor(data)
    -- Suppress aggression via modifier, preserving the base value
    -- so it can be cleanly restored if the perk is later lost.
    types.Actor.stats.ai.fight(pself).modifier = -200
    pself:sendEvent('RemoveAIPackages', 'Combat')
end

--- Removes the reversible calm modifier from a previously calmed ancestor.
--- @param data table|nil Unused event payload.
local function restoreAncestor(data)
    -- Zero the modifier to reverse calming. The base fight value
    -- was never changed, so the creature returns to its original
    -- aggression level.
    types.Actor.stats.ai.fight(pself).modifier = 0
end

-- ============================================================
--  COMBAT HIT HANDLER
--  Processes incoming hits on NPCs and creatures from the player.
--  MT lifesteal and IC Divine Smite share the same target-side
--  logic for both actor types.
-- ============================================================

local function registerActorHitHandler()
    if actorHitHandlerRegistered then
        return
    end
    local fw = framework()
    if fw == nil then
        return
    end

    fw.registerOnHitHandler({
        id = "FactionPerks_actor_target_effects",
        priority = 200,
    }, function(attack)
        -- Weapon hits only - melee or ranged, not spell damage
        if not (attack.sourceType == interfaces.Combat.ATTACK_SOURCE_TYPES.Melee or
            attack.sourceType == interfaces.Combat.ATTACK_SOURCE_TYPES.Ranged) then
            return
        end

        -- Player must be the attacker
        if (attack.attacker and attack.attacker.type ~= types.Player) then return end

        FPerks_DoMT4Attack(attack)

        -- Target must be smite-eligible
        if not FPerks_isSmiteTarget(pself) then return end

        local payload = {attack, pself}
        attack.attacker:sendEvent("FPerks_IC_CheckSmiteLevel", payload)
    end)
    actorHitHandlerRegistered = true
end

--- Applies direct health damage sent by player-side perk effects.
--- Damage is resolved through the framework calculation pipeline first so
--- other mods can contribute to `direct.damage.health`.
--- @param data table Event payload with amount and optional source/context data.
local function takeDamage(data)
    data = data or {}
    local fw = framework()
    if fw == nil then
        return
    end
    local health = types.Actor.stats.dynamic.health(pself)
    local before = health.current
    local applied = fw.applyActorResourceDelta({
        actor = pself,
        resource = "health",
        operation = fw.RESOURCE_OPERATION.Damage,
        amount = data.amount or 0,
        source = data.source,
        sourceEffect = data.sourceEffect,
        damageType = data.damageType,
        context = data,
    })
    if data.sourceEffect == "FactionPerks_IL_LegionaryResolve" then
        print("FactionPerks[IL]: target received Shield Wall amount="
            .. tostring(data.amount or 0)
            .. " applied=" .. tostring(applied)
            .. " healthBefore=" .. tostring(before)
            .. " healthAfter=" .. tostring(types.Actor.stats.dynamic.health(pself).current))
    end
end

--- Forwards Imperial Cult Smite payloads into the shared target-side resolver.
--- @param package table Smite attack/rank/level tuple.
local function doSmiteTrigger(package)
    FPerks_DoICSmite(package)
end

local function onUpdate()
    registerActorHitHandler()
end

return {
    eventHandlers = {
        [ns .. "_TT_CalmAncestor"]    = calmAncestor,
        [ns .. "_TT_RestoreAncestor"] = restoreAncestor,
        playerSneaking = FPerks_UpdatePlayerSneakStatus,
        FPerks_TakeDamage = takeDamage,
        DoICSmite = doSmiteTrigger,
    },
    engineHandlers = {
        onActive = onActive,
        onUpdate = onUpdate,
    }
}
