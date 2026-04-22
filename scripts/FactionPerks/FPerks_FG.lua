--[[

    FG:
        FPerks_FG1_Passive              - +3 Strength, +3 Endurance, +10 Fortify Health,
                                          +5 Long Blade, +5 Blunt Weapon, +5 Axe
        FPerks_FG2_Passive              - +5 Strength, +5 Endurance, +20 Fortify Health,
                                          +10 Long Blade, +10 Blunt Weapon, +10 Axe
        FPerks_FG3_Passive              - +10 Strength, +10 Endurance, +35 Fortify Health,
                                          +18 Long Blade, +18 Blunt Weapon, +18 Axe
        FPerks_FG4_Passive              - +15 Strength, +15 Endurance, +50 Fortify Health,
                                          +25 Long Blade, +25 Blunt Weapon, +25 Axe
        FPerks_FG3_Enrage               - Power, Fortify Health 50pts, Fortify Fatigue 200pts,
                                          Fortify Attack 100pts, 30s duration.
]]

local ns         = require("scripts.FactionPerks.namespace")
local utils      = require("scripts.FactionPerks.utils")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local ambient    = require('openmw.ambient')

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements

-- Create a table with all the Faction spell effects in it, each object is the perk of that rank
local perkTable = {
    [1] = { passive = {"FPerks_FG1_Passive"} },
    [2] = { passive = {"FPerks_FG2_Passive"} },
    [3] = { passive = {"FPerks_FG3_Passive"} },
    [4] = { passive = {"FPerks_FG4_Passive"} }
}

-- Perk id prep
local fg1_id = ns .. "_fg_dues_paid"
local fg2_id = ns .. "_fg_iron_discipline"
local fg3_id = ns .. "_fg_battle_tested"
local fg4_id = ns .. "_fg_champion_of_the_guild"

local setRank = utils.makeSetRank(perkTable, nil)

-- ============================================================
--  FIGHTERS GUILD COUNTER ATTACK - Iron Discipline (P2+)
--
--  When an enemy misses the player with a weapon swing, if the
--  player has a weapon equipped they immediately make a free
--  damage roll with it against the attacker.
--
--  Damage approximates the vanilla formula:
--    base  = random value around highest average damage type
--    x Strength factor (0.5 + 0.5 x str/100)
--    x Fatigue factor  (0.75 + 0.25 x currentFatigue/maxFatigue)
--
--  Cooldown: 10s at P2, 6s at P3, 1.5s at P4.
--  Each counter drains a small amount of player fatigue.
--
--  Sound reflects the attacker's armour weight so the feedback
--  feels grounded. Played as a 2D ambient sound since
--  playSound3d is restricted to self in local scripts.
-- ============================================================

local lastFGCounterTime = 0

local function getArmorHitSound(actor)
    -- Read the attacker's cuirass weight to approximate armour type.
    -- Thresholds are approximate for vanilla cuirass weights:
    --   Light  (Chitin, Netch Leather, Glass):    < 10
    --   Medium (Bonemold, Indoril):               10 - 25
    --   Heavy  (Iron, Steel, Orcish, Ebony):      > 25
    local cuirass = types.Actor.getEquipment(actor, types.Actor.EQUIPMENT_SLOT.Cuirass)
    if cuirass and types.Armor.objectIsInstance(cuirass) then
        local weight = types.Armor.record(cuirass).weight
        if weight < 10 then
            return "light armor hit"
        elseif weight < 25 then
            return "medium armor hit"
        else
            return "heavy armor hit"
        end
    end
    -- Unarmored or no cuirass - default to light
    return "light armor hit"
end

local function getCounterDamage(weapon, attacker)
    local rec = types.Weapon.record(weapon)

    -- Find the highest average damage type as the base for the strike
    local chop   = (rec.chopMinDamage   + rec.chopMaxDamage)   / 2
    local slash  = (rec.slashMinDamage  + rec.slashMaxDamage)  / 2
    local thrust = (rec.thrustMinDamage + rec.thrustMaxDamage) / 2
    local best   = math.max(chop, slash, thrust)

    -- Randomise around the best average (75% - 125% of it)
    local base = best * (0.75 + math.random() * 0.5)

    -- Strength factor: mirrors vanilla's roughly linear strength scaling
    local str       = types.Actor.stats.attributes.strength(attacker).modified
    local strFactor = 0.5 + 0.5 * (str / 100)

    -- Fatigue factor: penalises exhausted attackers
    local fatigue   = types.Actor.stats.dynamic.fatigue(attacker)
    local maxFat    = math.max(fatigue.base + fatigue.modifier, 1)
    local fatFactor = 0.75 + 0.25 * (fatigue.current / maxFat)

    return math.floor(base * strFactor * fatFactor)
end

interfaces.Combat.addOnHitHandler(function(attack)
    -- Weapon swings only - excludes hand-to-hand and spell damage
    if attack.successful             then return end
    if not attack.weapon             then return end
    if not (attack.attacker and attack.attacker:isValid()) then return end

    -- Player must hold at least FG P2
    if not R().hasPerk(fg2_id).check() then return end

    local cooldown = 10
    if     R().hasPerk(fg4_id).check() then cooldown = 1.5
    elseif R().hasPerk(fg3_id).check() then cooldown = 6
    end

    local now = core.getSimulationTime()
    if (now - lastFGCounterTime) < cooldown then return end

    -- Player must have a weapon equipped to counter with
    local playerWeapon = types.Actor.getEquipment(self, types.Actor.EQUIPMENT_SLOT.CarriedRight)
    if not playerWeapon                               then return end
    if not types.Weapon.objectIsInstance(playerWeapon) then return end

    -- Calculate and route counter damage through npc.lua/creature.lua
    local dmg = getCounterDamage(playerWeapon, self)
    attack.attacker:sendEvent("FPerks_TakeDamage", { amount = dmg })

    -- Small fatigue cost to represent the reactive strike
    local fatigue = types.Actor.stats.dynamic.fatigue(self)
    fatigue.current = math.max(0, fatigue.current - 8)

    -- Play armour-appropriate hit sound at the player's position (2D)
    ambient.playSound(getArmorHitSound(attack.attacker))

    lastFGCounterTime = now
    print("FG Counter Attack! Damage: " .. tostring(dmg))
end)

-- ============================================================
--  FIGHTERS GUILD
--  Primary attributes: Strength, Endurance
--  Scaling: Fortify Health, Long Blade, Blunt Weapon, Axe
--  Special: Enrage power (Battle Tested),
--           Counter attack on miss (Iron Discipline P2+)
-- ============================================================

local function guildRank(rank)
    local reqs = {
        R().minimumFactionRank('fighters guild', rank),
    }
    if core.contentFiles.has("tamriel_data.esm") then
        table.insert(reqs, R().minimumFactionRank('t_cyr_fightersguild', rank))
        table.insert(reqs, R().minimumFactionRank('t_sky_fightersguild', rank))
    end
    -- No need for orGroup if only one requirement
    if #reqs == 1 then return reqs[1] end
    return R().orGroup(table.unpack(reqs))
end

interfaces.ErnPerkFramework.registerPerk({
    id = fg1_id,
    localizedName = "Dues Paid",
    --hidden = true,
    localizedDescription = "The basic drills are already sharpening your edge.\n "
        .. "(+3 Strength, +3 Endurance, +10 Fortify Health, "
        .. "+5 Long Blade, +5 Blunt Weapon, +5 Axe)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        guildRank(0),
        R().minimumLevel(1)
    },
    onAdd = function()
        setRank(1)
    end,
    onRemove = function()
        setRank(nil)
    end
})

interfaces.ErnPerkFramework.registerPerk({
    id = fg2_id,
    localizedName = "Iron Discipline",
    --hidden = true,
    localizedDescription = "The Guild's contracts have hardened you. "
        .. "You wade into battle with the confidence of experience. "
        .. "When an enemy swings and misses, you punish the opening immediately.\n "
        .. "Requires Dues Paid. "
        .. "(+5 Strength, +5 Endurance, +20 Fortify Health, "
        .. "+10 Long Blade, +10 Blunt Weapon, +10 Axe)\n\n"
        .. "Counter Attack: When an enemy misses you with a weapon, "
        .. "you immediately strike back. 10s cooldown.",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(fg1_id),
        guildRank(3),
        R().minimumAttributeLevel('strength', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
    end,
    onRemove = function()
        setRank(nil)
    end
})

interfaces.ErnPerkFramework.registerPerk({
    id = fg3_id,
    localizedName = "Battle Tested",
    --hidden = true,
    localizedDescription = "Daedra, bandits, necromancers - you have killed them all on contract. "
        .. "When the moment demands it, you can call upon a terrifying fury. "
        .. "Your counter attack cooldown is reduced.\n "
        .. "Requires Iron Discipline. "
        .. "(+10 Strength, +10 Endurance, +35 Fortify Health, "
        .. "+18 Long Blade, +18 Blunt Weapon, +18 Axe, grants Martial Rage power)\n\n"
        .. "Counter Attack cooldown reduced to 6s.",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(fg2_id),
        guildRank(6),
        R().minimumAttributeLevel('strength', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        setRank(3)
        types.Actor.spells(self):add("FPerks_FG3_Enrage");
    end,
    onRemove = function()
        setRank(nil)
        types.Actor.spells(self):remove("FPerks_FG3_Enrage");
    end
})

interfaces.ErnPerkFramework.registerPerk({
    id = fg4_id,
    localizedName = "Champion of the Guild",
    --hidden = true,
    localizedDescription = "The Fighters Guild holds you as one of its finest. "
        .. "Your counter attack is now almost instantaneous.\n "
        .. "Requires Battle Tested. "
        .. "(+15 Strength, +15 Endurance, +50 Fortify Health, "
        .. "+25 Long Blade, +25 Blunt Weapon, +25 Axe)\n\n"
        .. "Counter Attack cooldown reduced to 1.5s.",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(fg3_id),
        guildRank(9),
        R().minimumAttributeLevel('strength', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
    end,
    onRemove = function()
        setRank(nil)
    end
})
