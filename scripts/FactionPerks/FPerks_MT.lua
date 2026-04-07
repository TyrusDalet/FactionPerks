 --[[
 MT:
        FPerks_MT1_Passive               - +5 Speed, +10 Short Blade, +10 Speechcraft
        FPerks_MT2_Passive               - +15 Speed(10), +25 Short Blade(15), +25 Light Armour 
        FPerks_MT3_Passive               - +25 Speed(15), +50 Sneak, +50 Short Blade(25)
        FPerks_MT4_Passive               - +25 Strength, +75 Short Blade(25), +75 Sneak(25)
        FPerks_MT2_Frenzy                - Spell, Frenzy, free, unlimited
        FPerks_MT4_Invisibility          - Spell, Invisibility, free, unlimited
        FPerks_MT4_Lifesteal             - Spell Effect, Absorb Life 25pts 5s
]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local ui         = require('openmw.ui')
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local nearby     = require('openmw.nearby')
local storage    = require('openmw.storage')
local async      = require('openmw.async')
local input      = require('openmw.input')


local perkStore = storage.playerSection("FactionPerks")
local hasMT4 = false

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements

--[[
-- Morag Tong Life Steal sneak attacks
    input.registerActionHandler(input.actions.Sneak.key, async:callback(function()
        for _, actor in pairs(nearby.actors) do
            actor:sendEvent("playerSneaking", not self.controls.sneak)
        end
    end))

    interfaces.Combat.addOnHitHandler(function(attack)
        if hasMT4 == true then --Checks to see if the player has the 4th Morag Tong perk
            if self.controls.sneak == true and attack.sourceType == "melee" and attack.successful == true then --If the player is Sneaking and the attack they make is a melee strike that hits
                -- Applies the Mephala's Kiss spell (FPerks_MT4_Lifesteal) to the target, with the player as the source
            end
        end
    end)
]]

-- ============================================================
--  MORAG TONG
--  Primary attribute: Speed
--  Scaling: Short Blade, Unarmored, Sneak
--  Special: Frenzy power (Blade Discipline),
--           Invisibility power (Honoured Executioner)
-- ============================================================

local mt1_id = ns .. "_mt_writ_bearer"
interfaces.ErnPerkFramework.registerPerk({
    id = mt1_id,
    localizedName = "Writ Bearer",
    --hidden = true,
    localizedDescription = "You carry the legal sanction of the Morag Tong. "
        .. "Your kills are honoured executions, not murders.\n "
        .. "(+5 Speed, +10 Short Blade, +10 Speechcraft)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('morag tong', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_MT1_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MT1_Passive");
    end,
})

local mt2_id = ns .. "_mt_blade_discipline"
interfaces.ErnPerkFramework.registerPerk({
    id = mt2_id,
    localizedName = "Blade Discipline",
    --hidden = true,
    localizedDescription = "The Tong teaches economy of motion. Your strikes are precise "
        .. "and swift. You have learned to channel pure battle-fury at will.\n "
        .. "Requires Writ Bearer. "
        .. "(+15 Speed, +25 Short Blade, +25 Light Armour, grants Frenzy power)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(mt1_id),
        R().minimumFactionRank('morag tong', 3),
        R().minimumAttributeLevel('speed', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_MT2_Passive");
        types.Actor.spells(self):add("FPerks_MT2_Frenzy");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MT2_Passive");
        types.Actor.spells(self):remove("FPerks_MT2_Frenzy");
    end,
})

local mt3_id = ns .. "_mt_calm_before"
interfaces.ErnPerkFramework.registerPerk({
    id = mt3_id,
    localizedName = "Calm Before",
    --hidden = true,
    localizedDescription = "You have learned the art of stillness. "
        .. "A Tong assassin who cannot wait cannot succeed.\n "
        .. "Requires Blade Discipline. "
        .. "(+25 Speed, +50 Sneak, +50 Short Blade)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(mt2_id),
        R().minimumFactionRank('morag tong', 6),
        R().minimumAttributeLevel('speed', 50),
        R().minimumLevel(10),
    },
    oonAdd = function()
        types.Actor.spells(self):add("FPerks_MT3_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MT3_Passive");
    end,
})

local mt4_id = ns .. "_mt_honoured_executioner"
interfaces.ErnPerkFramework.registerPerk({
    id = mt4_id,
    localizedName = "Honoured Executioner",
    --hidden = true,
    localizedDescription = "The Grand Master himself has commended your work. "
        .. "The shadows open for you whenever you call upon them.\n "
        .. "Requires Calm Before. "
        .. "(+25 Strength, +75 Short Blade, grants Invisibility power)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(mt3_id),
        R().minimumFactionRank('morag tong', 9),
        R().minimumAttributeLevel('speed', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_MT4_Passive");
        types.Actor.spells(self):add("FPerks_MT4_Invisibility");
        hasMT4 = true
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MT4_Passive");
        types.Actor.spells(self):remove("FPerks_MT4_Invisibility");
        hasMT4 = false
    end,
})
