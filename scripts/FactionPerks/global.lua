--[[
    FactionPerks global.lua

    Handles effects that require global script access:

    House Hlaalu — merchant Disposition + Mercantile effects:
        FPerks_HH_ApplyMerchant   — apply modifiers to a specific NPC when dialogue opens.
                                    Used by both Hlaalu merchant buff and Hlaalu/Telvanni
                                    P4 disposition penalty (merc = 0 for penalty).
        FPerks_HH_RemoveMerchant  — reverse the above when dialogue closes.

    House Redoran P4 — bounty doubling:
        FPerks_HR_DoubleBounty    — receives the organic bounty increase detected by the
                                    player script and adds the same amount again.
                                    data.increase is the amount to add.
]]

local world = require('openmw.world')
local types = require('openmw.types')

-- ============================================================
--  HLAALU MERCHANT DISPOSITION
--  modifyBaseDisposition is global-only, so player.lua
--  sends us the NPC object + the values to apply/remove.
-- ============================================================

local function onApplyMerchant(data)
    local npc    = data.npc
    local player = world.players[1]
    if not npc or not npc:isValid() then return end
    types.NPC.modifyBaseDisposition(npc, player, data.disp)
    -- Mercantile is a skill modifier; adjust via NPC stats
    local ms = types.NPC.stats.skills.mercantile(npc)
    if ms then ms.modifier = ms.modifier + data.merc end
end

local function onRemoveMerchant(data)
    local npc    = data.npc
    local player = world.players[1]
    if not npc or not npc:isValid() then return end
    types.NPC.modifyBaseDisposition(npc, player, -data.disp)
    local ms = types.NPC.stats.skills.mercantile(npc)
    if ms then ms.modifier = ms.modifier - data.merc end
end

-- ============================================================
--  REDORAN BOUNTY DOUBLING
--  Player script detects the organic increase; we apply it again.
--  setCrimeLevel is global-only.
-- ============================================================

local function onDoubleBounty(data)
    local player = world.players[1]
    local cur    = types.Player.getCrimeLevel(player)
    if cur then
        types.Player.setCrimeLevel(player, cur + data.increase)
    end
end

-- ============================================================
--  RETURN
-- ============================================================
return {
    eventHandlers = {
        FPerks_HH_ApplyMerchant  = onApplyMerchant,
        FPerks_HH_RemoveMerchant = onRemoveMerchant,
        FPerks_HR_DoubleBounty   = onDoubleBounty,
    },
}
