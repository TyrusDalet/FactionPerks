--[[

    IL:
        FPerks_IL1_Passive          - +5 Endurance, +10 Fortify Fatigue, +10 Medium Armour, +10 Heavy Armour
        FPerks_IL2_Passive          - +15(10) Endurance, +25(15) Fortify Fatigue, +25 Block
        FPerks_IL3_Passive          - +25(10) Endurance, +50(25) Fortify Fatigue, +50 Athletics
        FPerks_IL4_Passive          - +25 Strength, +75(25) Fortify Fatigue, +75(65) Heavy Armour, Restore Health 1pt/s, Restore Fatigue 1pt/s
        FPerks_IL3_Prowess          

]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements

-- ============================================================
--  IMPERIAL LEGION
--  Primary attribute: Endurance
--  Scaling: Fortify Fatigue
--  Special: vanilla Adrenaline Rush power (Forced March),
--           Restore Health + Fatigue ability (Legate)
-- ============================================================

local il1_id = ns .. "_il_legion_recruit"
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
        R().minimumLevel(1),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_IL1_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_IL1_Passive");
    end
})

local il2_id = ns .. "_il_shield_wall"
interfaces.ErnPerkFramework.registerPerk({
    id = il2_id,
    localizedName = "Shield Wall",
    --hidden = true,
    localizedDescription = "You have mastered the disciplined defensive formations of the Imperial army. \n"
        .. "Requires Legion Recruit. "
        .. "(+15 Endurance, +25 Fortify Fatigue, +25 Block)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(il1_id),
        R().minimumFactionRank('imperial legion', 3),
        R().minimumAttributeLevel('endurance', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
    types.Actor.spells(self):add("FPerks_IL2_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_IL2_Passive");
    end
})

local il3_id = ns .. "_il_forced_march"
interfaces.ErnPerkFramework.registerPerk({
    id = il3_id,
    localizedName = "Forced March",
    --hidden = true,
    localizedDescription = "The Legion demands its soldiers keep pace regardless of terrain. "
        .. "When the situation demands it, you can push far beyond normal limits.\n "
        .. "Requires Shield Wall. "
        .. "(+25 Endurance, +50 Fortify Fatigue, +50 Athletics, grants Legion's Prowess power)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(il2_id),
        R().minimumFactionRank('imperial legion', 6),
        R().minimumAttributeLevel('endurance', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_IL3_Passive");
        types.Actor.spells(self):add("FPerks_IL3_Prowess");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_IL3_Passive");
        types.Actor.spells(self):remove("FPerks_IL3_Prowess");
    end
})

local il4_id = ns .. "_il_legate"
interfaces.ErnPerkFramework.registerPerk({
    id = il4_id,
    localizedName = "Legate",
    --hidden = true,
    localizedDescription = "You command the respect of every soldier who serves alongside you. "
        .. "The Emperor's discipline has forged your body into something that endures.\n "
        .. "Requires Forced March. "
        .. "(+25 Strength, +75 Fortify Fatigue, +75 Heavy Armour, Restore Health 1pt/s, Restore Fatigue 1pt/s)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(il3_id),
        R().minimumFactionRank('imperial legion', 9),
        R().minimumAttributeLevel('endurance', 75),
        R().minimumLevel(15),
    },
     onAdd = function()
        types.Actor.spells(self):add("FPerks_IL4_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_IL4_Passive");
    end
})
