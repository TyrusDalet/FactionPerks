local interfaces = require('openmw.interfaces')
local types = require('openmw.types')
local pself = require('openmw.self')

require("scripts.FactionPerks.shared")

-- ============================================================
--  COMBAT HIT HANDLER
--  Processes incoming hits on NPCs from the player.
--  MT lifesteal (FPerks_DoMT4Attack) fires on successful
--  sneaking weapon attacks against NPCs.
--  IC Divine Smite (FPerks_DoICSmite) fires on weapon hits
--  against undead, daedra, and vampire NPC targets.
--  Strength of the Redoran is a separate player-side effect
--  and has no interaction here.
-- ============================================================

interfaces.Combat.addOnHitHandler(function(attack)
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

    print("Sending Smite Event")
    local target = pself
    local payload = {attack, target}
    attack.attacker:sendEvent("FPerks_IC_CheckSmiteLevel", payload)
end)

local function takeDamage(data)
    local health = types.Actor.stats.dynamic.health(pself)
    health.current = health.current - data.amount
end

function DoSmiteTrigger(package)
    FPerks_DoICSmite(package)
end

return {
    eventHandlers = {
        playerSneaking = FPerks_UpdatePlayerSneakStatus,
        FPerks_TakeDamage = takeDamage,
        DoICSmite = DoSmiteTrigger,
    }
}
