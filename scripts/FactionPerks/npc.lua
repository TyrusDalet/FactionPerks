local I = require('openmw.interfaces')

require("scripts.FactionPerks.shared")

I.Combat.addOnHitHandler(function(attack)
    DoMT4Attack(attack)
end)

return {
    eventHandlers = {
        playerSneaking = UpdatePlayerSneakStatus,
    }
}
