--[[
    HR:
        FPerks_HR1_Passive          - +5 Endurance, +10 Spear, +10 Athletics
        FPerks_HR2_Passive          - +15 Endurance, +25 Heavy Armor, +25 Block
        FPerks_HR3_Passive          - +25 Endurance, +50 Spear, +50 Block
        FPerks_HR4_Passive          - +25 Strength, +75 Spear, +75 Heavy Armor

    P4 special:
        Guardian's Fury: base Strength and Endurance added as a modifier (doubles them).
        Recalculates on level-up. Stripped on perk removal.
        Bounty doubling: any crime increase is doubled via global script.

    DOWNSIDE at P4: all Bounty received is doubled.
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

local R = interfaces.ErnPerkFramework.requirements

-- Create a table with all the Faction spell effects in it, each object is the perk of that rank
local perkTable = {
    [1] = { passive = {"FPerks_HR1_Passive"} },
    [2] = { passive = {"FPerks_HR2_Passive"} },
    [3] = { passive = {"FPerks_HR3_Passive"} },
    [4] = { passive = {"FPerks_HR4_Passive"} },
}

-- Increase the rank of the PerkTable, applying the new effects, and removing the old one.
local function setRank(NewRank)
-- Removes all other effects by iterating through the table, then for each object within THAT table, runs through those

    -- Removing
    for _, rankData in pairs(perkTable) do
    -- Remove spell effects
        if rankData.passive then --If the object in that table location is a passive (spell effect) run a command to remove it
            for i = 1, #rankData.passive do
                types.Actor.spells(self):remove(rankData.passive[i])
            end
        end
    end

-- Stop here if no rank (used for onRemove)
    if not NewRank or not perkTable[NewRank] then return end

    local rankData = perkTable[NewRank]

    -- Add spell effects
    if rankData.passive then --If the object in that table location is a passive (spell effect) run a command to add it
        for i = 1, #rankData.passive do
            types.Actor.spells(self):add(rankData.passive[i])
        end
    end
end

-- ============================================================
--  GUARDIAN'S FURY - Strength + Endurance doubling
--  Reads base values and sets an equal modifier, recalculated
--  on level-up. Bounty doubling is handled by global.lua since
--  types.Player.setCrimeLevel is global-script-only.
-- ============================================================

local hasRedoranDouble  = false
local redoranStrApplied = 0
local redoranEndApplied = 0

-- Bounty tracking
local hasRedoranBounty   = false
local lastOrganicBounty  = 0
local redoranBountyAdded = 0
local bountyCheckTimer   = 0
local BOUNTY_CHECK_RATE  = 1.0

local function getTrueBase(attrName)
    local stat = types.Actor.stats.attributes[attrName](self)
    -- Active ability fortifications get folded into .base from Lua's
    -- perspective, so we subtract them out to get the real character base.
    local fx = types.Actor.activeEffects(self):getEffect("fortifyattribute", attrName)
    local fortified = fx and fx.magnitude or 0
    return stat.base - fortified
end

local function applyRedoranDouble()
    if not hasRedoranDouble then return end
    local strStat = types.Actor.stats.attributes.strength(self)
    local endStat = types.Actor.stats.attributes.endurance(self)
    -- Strip previous modifier before recalculating
    strStat.modifier = strStat.modifier - redoranStrApplied
    endStat.modifier = endStat.modifier - redoranEndApplied
    -- Read true base without ability fortifications
    redoranStrApplied = getTrueBase("strength")
    redoranEndApplied = getTrueBase("endurance")
    strStat.modifier = strStat.modifier + redoranStrApplied
    endStat.modifier = endStat.modifier + redoranEndApplied
end

local function removeRedoranDouble()
    local strStat = types.Actor.stats.attributes.strength(self)
    local endStat = types.Actor.stats.attributes.endurance(self)
    strStat.modifier = strStat.modifier - redoranStrApplied
    endStat.modifier = endStat.modifier - redoranEndApplied
    redoranStrApplied = 0
    redoranEndApplied = 0
end

-- ============================================================
--  onUpdate
-- ============================================================

local lastLevel = 0

local function onUpdate(dt)
    -- Level-up: recalculate Guardian's Fury
    local currentLevel = types.Actor.stats.level(self).current
    if hasRedoranDouble and currentLevel ~= lastLevel and lastLevel ~= 0 then
        applyRedoranDouble()
    end
    lastLevel = currentLevel

    -- Bounty doubling: detect increases and send to global script
    if hasRedoranBounty then
        bountyCheckTimer = bountyCheckTimer - dt
        if bountyCheckTimer <= 0 then
            bountyCheckTimer = BOUNTY_CHECK_RATE
            local cur = types.Player.getCrimeLevel(self)
            if cur then
                local organicBounty = cur - redoranBountyAdded
                if organicBounty > lastOrganicBounty then
                    local increase = organicBounty - lastOrganicBounty
                    -- Ask global script to apply the doubling
                    core.sendGlobalEvent("FPerks_HR_DoubleBounty", {
                        increase = increase,
                    })
                    redoranBountyAdded = redoranBountyAdded + increase
                    lastOrganicBounty  = organicBounty
                elseif organicBounty < lastOrganicBounty then
                    -- Bounty was paid off or reduced; resync
                    lastOrganicBounty  = math.max(0, organicBounty)
                    redoranBountyAdded = math.max(0, cur - lastOrganicBounty)
                end
            end
        end
    end
end

-- ============================================================
--  HOUSE REDORAN
--  Primary attribute: Endurance (P1-P3), Strength (P4)
--  Scaling: Spear, Athletics, Heavy Armor, Block
--  Special P4: Guardian's Fury - Strength and Endurance doubled,
--              recalculates on level-up.
--              DOWNSIDE: Bounty received is doubled.
-- ============================================================

local hr1_id = ns .. "_hr_redoran_pledge"
interfaces.ErnPerkFramework.registerPerk({
    id = hr1_id,
    localizedName = "Redoran Pledge",
    --hidden = true,
    localizedDescription = "You have pledged yourself to House Redoran's code of duty and honour.\n "
        .. "(+5 Endurance, +10 Spear, +10 Athletics)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('redoran', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() setRank(1) end,
    onRemove = function() setRank(nil) end,
})

local hr2_id = ns .. "_hr_burden_of_duty"
interfaces.ErnPerkFramework.registerPerk({
    id = hr2_id,
    localizedName = "Burden of Duty",
    --hidden = true,
    localizedDescription = "Redoran warriors do not complain - they endure. "
        .. "The weight of armour and obligation have become one and the same to you.\n "
        .. "Requires Redoran Pledge. "
        .. "(+15 Endurance, +25 Heavy Armor, +25 Block)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(hr1_id),
        R().minimumFactionRank('redoran', 3),
        R().minimumAttributeLevel('endurance', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() setRank(2) end,
    onRemove = function() setRank(nil) end,
})

local hr3_id = ns .. "_hr_unbroken_line"
interfaces.ErnPerkFramework.registerPerk({
    id = hr3_id,
    localizedName = "Unbroken Line",
    --hidden = true,
    localizedDescription = "House Redoran does not retreat. You have internalised this truth "
        .. "until it became something closer to armour than principle.\n "
        .. "Requires Burden of Duty. "
        .. "(+25 Endurance, +50 Spear, +50 Block)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(hr2_id),
        R().minimumFactionRank('redoran', 6),
        R().minimumAttributeLevel('endurance', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() setRank(3) end,
    onRemove = function() setRank(nil) end,
})

local hr4_id = ns .. "_hr_guardian_of_the_house"
interfaces.ErnPerkFramework.registerPerk({
    id = hr4_id,
    localizedName = "Guardian of the House",
    --hidden = true,
    localizedDescription = "You are House Redoran's shield made flesh. Your honour is "
        .. "unimpeachable, your resolve unyielding - and your strength and endurance "
        .. "are doubled while you stand, growing further each time you level up.\n "
        .. "But a Guardian of the House is held to a higher standard than any common soldier. "
        .. "The guards and magistrates of Vvardenfell know your name, and any crime you "
        .. "commit reflects on the House itself - doubling the shame, and the bounty that follows.\n "
        .. "Requires Unbroken Line. "
        .. "(+25 Strength, +75 Spear, +75 Heavy Armor, "
        .. "base Strength and Endurance doubled as modifier, recalculates on level-up.\n "
        .. "DOWNSIDE: all Bounty received is doubled.)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(hr3_id),
        R().minimumFactionRank('redoran', 9),
        R().minimumAttributeLevel('endurance', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        setRank(4)
        hasRedoranDouble   = true
        hasRedoranBounty   = true
        lastOrganicBounty  = types.Player.getCrimeLevel(self) or 0
        redoranBountyAdded = 0
        bountyCheckTimer   = 0
        applyRedoranDouble()
    end,
    onRemove = function()
        setRank(nil)
        removeRedoranDouble()
        hasRedoranDouble   = false
        hasRedoranBounty   = false
        lastOrganicBounty  = 0
        redoranBountyAdded = 0
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================
return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
}
