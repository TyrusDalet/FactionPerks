--[[

    MG:
        FPerks_MG1_Passive          - +5 Intelligence, +10 Fortify Magicka
        FPerks_MG2_Passive          - +15(10) Intelligence, +25(15) Fortify Magicka
        FPerks_MG3_Passive          - +25(10) Intelligence, +50(25) Fortify Magicka, 0.5xINT Max Magicka
        FPerks_MG4_Passive          - +25 Willpower, +75(25) Fortify Magicka, 1.0XINT (0.5) Max Magicka

]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local storage    = require('openmw.storage')

local perkStore = storage.playerSection("FactionPerks")

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements

-- ============================================================
--  MAGES GUILD
--  Primary attribute: Intelligence
--  Scaling: Fortify Magicka (flat) + INT-scaled bonus at P3/P4
-- ============================================================

local mg1_id = ns .. "_mg_guild_initiate"
interfaces.ErnPerkFramework.registerPerk({
    id = mg1_id,
    localizedName = "Guild Initiate",
    --hidden = true,
    localizedDescription = "You have passed the Guild's entrance rites. "
        .. "The library shelves are open to you.\n "
        .. "(+5 Intelligence, +10 Fortify Magicka)",
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('mages guild', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_MG1_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MG1_Passive");
    end,
})

local mg2_id = ns .. "_mg_scholastic_rigour"
interfaces.ErnPerkFramework.registerPerk({
    id = mg2_id,
    localizedName = "Scholastic Rigour",
    --hidden = true,
    localizedDescription = "The Guild's structured study has sharpened your mind considerably.\n "
        .. "Requires Guild Initiate. "
        .. "(+15 Intelligence, +25 Fortify Magicka)",
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(mg1_id),
        R().minimumFactionRank('mages guild', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
        onAdd = function()
        types.Actor.spells(self):add("FPerks_MG2_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MG2_Passive");
    end,
})

local mg3_id = ns .. "_mg_arcane_reservoir"
interfaces.ErnPerkFramework.registerPerk({
    id = mg3_id,
    localizedName = "Arcane Reservoir",
    --hidden = true,
    localizedDescription = "Years of disciplined spellcasting have deepened your reserves. "
        .. "Your magicka pool expands with your intellect.\n "
        .. "Requires Scholastic Rigour. "
        .. "(+25 Intelligence, +50 Fortify Magicka, "
        .. "Fortify Maximum Magicka 0.5x Intelligence)",
    art = "textures\\levelup\\mage", cost = 3,
    requirements = {
        R().hasPerk(mg2_id),
        R().minimumFactionRank('mages guild', 6),
        R().minimumAttributeLevel('intelligence', 50),
        R().minimumLevel(10),
    },
        onAdd = function()
        types.Actor.spells(self):add("FPerks_MG3_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MG3_Passive");
    end,
})

local mg4_id = ns .. "_mg_archmagisters_peer"
interfaces.ErnPerkFramework.registerPerk({
    id = mg4_id,
    localizedName = "Archmagister's Peer",
    --hidden = true,
    localizedDescription = "The senior mages regard you as a genuine equal. "
        .. "Your intellect feeds your power directly.\n "
        .. "Requires Arcane Reservoir. "
        .. "(+25 Willpower, +75 Fortify Magicka, "
        .. "Fortify Maximum Magicka 1.0x Intelligence [replaces Arcane Reservoir's 0.5x bonus])",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(mg3_id),
        R().minimumFactionRank('mages guild', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
        onAdd = function()
        types.Actor.spells(self):add("FPerks_MG4_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_MG4_Passive");
    end,
})
