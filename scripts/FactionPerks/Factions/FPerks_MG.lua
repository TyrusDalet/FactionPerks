--[[
    MG:
        FPerks_MG1_Passive          - +3 Intelligence, +3 Willpower,
                                      +10 Fortify Magicka, +5 Destruction, +5 Alteration
        FPerks_MG2_Passive          - +5 Intelligence, +5 Willpower,
                                      +20 Fortify Magicka, +10 Destruction, +10 Alteration
        FPerks_MG3_Passive          - +10 Intelligence, +10 Willpower,
                                      +35 Fortify Magicka, +18 Destruction, +18 Alteration,
                                      Fortify Maximum Magicka 0.5x Intelligence (magnitude 5)
        FPerks_MG4_Passive          - +15 Intelligence, +15 Willpower,
                                      +50 Fortify Magicka, +25 Destruction, +25 Alteration,
                                      Fortify Maximum Magicka 1.0x Intelligence (magnitude 10)

    NOTE: Fortify Magicka is applied via stat.modifier so the maximum is raised correctly.
    Fortify Maximum Magicka (MG3/MG4) is a distinct effect and remains in the ESP.

    All character-specific data (visited Places of Power, applied effect values,
    and appliedMagickaMod) is persisted via onSave/onLoad so it is isolated per
    character and per save.

    Magical Cartography (P2+):
        Visiting Places of Power builds two scaling bonuses:
            Per location visited:    +1 Resist Magicka, +2 Detect Enchantment
            Per 10 locations:        +5% magicka refund on successful spell cast (max 25%)

        Console commands (type in the in-game console):
            luamg cartography dump  - prints all stored Places of Power for this character
            luamg cartography clear - wipes this character's visited table and resets effects
]]

local ns          = "FactionPerks"
local utils       = require("scripts.FactionPerks.utils")
local FactionGroupRank = utils.FactionGroupRank
local perkHidden  = utils.perkHidden
local GUILD        = utils.FACTION_GROUPS.magesGuild
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local core        = require('openmw.core')
local ui          = require('openmw.ui')

local R = utils.requirements()

local perkTable = {
    [1] = { attributes = { willpower=3,  intelligence=3  }, skills = { destruction=5,  alteration=5  } },
    [2] = { attributes = { willpower=5,  intelligence=5  }, skills = { destruction=10, alteration=10 } },
    [3] = { attributes = { willpower=10, intelligence=10 },
            skills = { destruction=18, alteration=18 },
            passive = {"FPerks_MG4_Max_Magicka_1"} },
    [4] = { attributes =
            { willpower=15, intelligence=15 },
            skills = { destruction=25, alteration=25 },
            passive = {"FPerks_MG4_Max_Magicka_2"} },
}

local appliedStats = { attributes = {}, skills = {} }

local setRank = utils.makeSetRank(perkTable, nil, appliedStats)

-- ============================================================
--  AAM INTEGRATION
--  Reports current active stat modifiers to AbilitiesAsModifiers
--  so they appear as a labelled source in attribute/skill tooltips.
--  Called after every setRank invocation.
-- ============================================================
local FACTION_DISPLAY_NAME = "Mage's Guild Perks"

local mg1_id = ns .. "_mg_guild_initiate"
local mg2_id = ns .. "_mg_scholastic_rigour"
local mg3_id = ns .. "_mg_arcane_reservoir"
local mg4_id = ns .. "_mg_archmagisters_peer"

local function getMGRank()
    return utils.highestOwnedPerkRank({
        [1] = mg1_id,
        [2] = mg2_id,
        [3] = mg3_id,
        [4] = mg4_id,
    })
end

local reportAAM = utils.makeAAMReporter(FACTION_DISPLAY_NAME, perkTable, getMGRank)

-- ============================================================
--  CHARACTER-SPECIFIC STATE
--  All of these are saved/loaded via onSave/onLoad.
-- ============================================================

local appliedMagickaMod = 0  -- current value written to stat.modifier
local appliedResist     = 0  -- current Resist Magicka bonus applied
local appliedDetect     = 0  -- current Detect Enchantment bonus applied
local visited           = {} -- map of cellId -> cellName for this character
local lastAppliedMGRank = nil

local MAGICKA_MOD_BY_RANK = {
    [0] = 0,
    [1] = 10,
    [2] = 20,
    [3] = 35,
    [4] = 50,
}

-- ============================================================
--  FORTIFY MAGICKA - stat.modifier approach
-- ============================================================

local function applyMagickaMod(value)
    local s = types.Actor.stats.dynamic.magicka(self)
    local delta = value - appliedMagickaMod --Calculate difference between new value and existing value
    s.modifier = s.modifier + delta -- Applies the delta to the magicka modifier
    local newMax = s.base + s.modifier -- Caclulate new maximum magicka
    if delta > 0 then
        s.current = math.min(s.current + delta, newMax) --Sets current magicka to current increased by the delta - or max magicka, whichever is lower, following vanilla Fortify logic
    elseif delta < 0 then
        s.current = math.min(s.current, newMax) --Sets current magicka to the lower of current magicka, or the new maximum after the delta was removed from the player
    end
    appliedMagickaMod = value
end
-- ============================================================
--  MAGICAL CARTOGRAPHY - Scholastic Rigour (P2+)
-- ============================================================

local hasMGCartography = false
local lastCellId       = nil
local cellCheckTimer   = 0
local CELL_CHECK_INTERVAL = 2.0

-- ============================================================
--  LOCATION DETECTION
-- ============================================================

local UNIQUE_LOCATIONS = {
    -- A location is a Place of Power if it is something magically powerful, or is the location of magical phenomena
    -- It can't be easily accessed by the Imperial Mages Guild
    -- Or has been sealed away (in the case of the entrance hall)

    -- Vanilla
    ["akulakhan's chamber"] = true,
    ["vivec, palace of vivec"]     = true,
    ["mournhold temple: high chapel"]         = true,
    ["sotha sil, dome of sotha sil"]   = true,
    ["magas volar"]   = true,
    ["solstheim, mortrag glacier: huntsman's hall"]   = true,
    ["shrine of azura"] = true,
    ["bamz-amschend, skybreak gallery"] = true,
    ["norenen-dur, basilica of divine whispers"] = true,

    -- TR
    ["vorthas uldun, chambers of methats uldun"]   = true,
    ["mala tor, lattagarlas"]   = true,
    ["old ebonheart, guild of mages: entrance hall"]   = true,
    ["the space gone missing, outer caverns"]   = true,
    ["emmurbalpitu, crepuscular shrine"] = true,

    -- PT
    ["garlas agea, aransel"] = true,
    ["nefa, starlight sanctum"] = true,
    ["garlas malatar, carac abaran"] = true,

    -- SHotN
    ["angturiel, cloudshaper dome"] = true,
    ["braignainesaide, marbaildomuin"] = true,
}

--- Checks a single cell identifier/name against the Cartography location rules.
--- Exact Places of Power are matched by full lower-case key; generic shrine and
--- propylon locations are matched by stable substrings.
--- @param cellKey string|nil Cell name or id.
--- @return boolean isMatch True if the key identifies a Place of Power.
local function isPlaceOfPowerKey(cellKey)
    if type(cellKey) ~= "string" then return false end
    local lower = cellKey:lower()
    if lower:find("inner shrine",     1, true) then return true end

    -- Tries to ensure that any Shrine is included, as long as that's it's only type, and not followed by anything subsequent
    if lower:find(", shrine",     1, true) and not lower:find(", shrine,",     1, true) and not lower:find(", shrine:",     1, true) then return true end

    if lower:find("propylon chamber", 1, true) then return true end
    if UNIQUE_LOCATIONS[lower]                 then return true end
    return false
end

--- Returns true when either the cell name or id identifies a Place of Power.
--- Some OpenMW cells expose the useful location string through `id`, while
--- others expose it through `name`, so Cartography checks both.
--- @param cellName string|nil Display name reported by OpenMW.
--- @param cellId string|nil Cell id reported by OpenMW.
--- @return boolean isMatch True when the current cell is a Place of Power.
local function isPlaceOfPower(cellName, cellId)
    return isPlaceOfPowerKey(cellName) or isPlaceOfPowerKey(cellId)
end

-- ============================================================
--  VISITED COUNT AND REFUND CALCULATION
-- ============================================================

local function getVisitedCount()
    local count = 0
    for _ in pairs(visited) do count = count + 1 end
    return count
end

local function getRefundPercent(count)
    return math.min(math.floor(count / 10) * 0.05, 0.25)
end

-- ============================================================
--  EFFECT APPLICATION
--  Uses delta-based modification so repeated calls (including
--  on load after restoring values from the save) never
--  double-apply the bonus.
-- ============================================================

local function applyCartographyEffects(count)
    local activeEffects = types.Actor.activeEffects(self)

    local targetResist = count
    local targetDetect = count * 2

    local deltaResist = targetResist - appliedResist
    local deltaDetect = targetDetect - appliedDetect

    if deltaResist ~= 0 then
        activeEffects:modify(deltaResist, "resistmagicka")
        appliedResist = targetResist
    end
    if deltaDetect ~= 0 then
        activeEffects:modify(deltaDetect, "detectenchantment")
        appliedDetect = targetDetect
    end
end

local function removeCartographyEffects()
    applyCartographyEffects(0)
end

-- ============================================================
--  CELL DISCOVERY
-- ============================================================

local function checkCurrentCell(currentCell)
    if not currentCell then return end

    local cellName = currentCell.name
    local cellId = currentCell.id

    if not isPlaceOfPower(cellName, cellId) then return end

    local visitKey = type(cellId) == "string" and cellId ~= "" and cellId or cellName
    if type(visitKey) ~= "string" or visitKey == "" then return end
    if visited[visitKey] then return end

    local oldCount = getVisitedCount()
    local displayName = type(cellName) == "string" and cellName ~= "" and cellName or visitKey
    visited[visitKey] = displayName
    local newCount = oldCount + 1

    applyCartographyEffects(newCount)

    local oldMilestone = math.floor(oldCount / 10)
    local newMilestone = math.floor(newCount / 10)

    if newMilestone > oldMilestone and newMilestone <= 5 then
        local refundPct = newMilestone * 5
        ui.showMessage("Magical Cartography: " .. newCount
            .. " Places of Power catalogued. Resist Magicka +" .. newCount
            .. ". Spell refund: " .. refundPct .. "%.")
    else
        ui.showMessage("Magical Cartography: Place of Power catalogued. ("
            .. newCount .. " total) Resist Magicka +" .. newCount .. ".")
    end

    utils.debug(2, "MG", "Cartography discovered '" .. tostring(displayName)
        .. "' (total: " .. newCount .. ")")
end

--- Applies the effective Mages Guild perk rank from one central path.
--- This keeps stat modifiers, AAM reporting, and Cartography state aligned
--- whether the rank changes through normal purchase, respec, load sync, or a
--- recovery pass after an interrupted onAdd/onRemove sequence.
--- @param rank number|nil Effective owned rank, or nil/0 for no MG perk.
--- @param reason string|nil Debug label for why reconciliation ran.
local function applyMGRank(rank, reason)
    rank = tonumber(rank) or 0
    if rank < 0 then rank = 0 end
    if rank > 4 then rank = 4 end

    local targetMagicka = MAGICKA_MOD_BY_RANK[rank] or 0
    local targetCartography = rank >= 2

    if lastAppliedMGRank == rank
        and appliedMagickaMod == targetMagicka
        and hasMGCartography == targetCartography then
        return
    end

    setRank(rank > 0 and rank or nil)
    applyMagickaMod(targetMagicka)
    hasMGCartography = targetCartography
    lastAppliedMGRank = rank

    if hasMGCartography then
        lastCellId = nil
        cellCheckTimer = 0
        applyCartographyEffects(getVisitedCount())
        checkCurrentCell(self.cell)
    else
        removeCartographyEffects()
    end

    reportAAM()
    utils.debug(1, "MG", "Applied owned rank " .. tostring(rank)
        .. " via " .. tostring(reason or "sync"))
end

--- Reconciles local MG effect state from the Framework-owned perk list.
--- This is a defensive recovery path for saves/respecs where the Framework
--- player perk list says MG perks are owned but a local effect flag was skipped.
--- @param reason string|nil Debug label for the reconciliation pass.
local function reconcileOwnedMGRank(reason)
    applyMGRank(getMGRank(), reason)
end

-- ============================================================
--  SPELL CAST REFUNDS
-- ============================================================

local MAGIC_SKILLS = {
    destruction = true, restoration = true, conjuration = true,
    mysticism   = true, illusion    = true, alteration  = true,
}

interfaces.ErnPerkFramework.registerSkillUseHandler({
    id = "FactionPerks_mages_guild_cartography_refund",
    playerCastOnly = true,
    priority = 200,
}, function(event)
    if not hasMGCartography                  then return end
    if not MAGIC_SKILLS[event.skillId]        then return end
    if event.cost <= 0                       then return end

    local count         = getVisitedCount()
    local refundPercent = getRefundPercent(count)
    if refundPercent <= 0 then return end

    local refundAmount = math.floor(event.cost * refundPercent)
    if refundAmount <= 0 then return end

    local magicka    = types.Actor.stats.dynamic.magicka(self)
    local maxMagicka = magicka.base + magicka.modifier
    magicka.current  = math.min(magicka.current + refundAmount, maxMagicka)

    ui.showMessage("Magical Cartography: Refunded " .. refundAmount .. " magicka.")
    utils.debug(2, "MG", "Cartography refunded " .. refundAmount
        .. " magicka (" .. (refundPercent * 100) .. "% of " .. event.cost .. ")")
end)

-- ============================================================
--  CARTOGRAPHY CONSOLE COMMANDS
--
--  luamg cartography dump  - print all stored Places of Power
--  luamg cartography clear - wipe visited table, reset effects
--  luamg debug             - prints debug information
-- ============================================================

--- Checks whether a normalized command targets the Mages Guild command namespace.
--- Accepts `mg`, `magesguild`, and `mages guild` so bug reports using the full
--- faction name do not silently miss the short debug alias.
--- @param lower string Normalized lower-case command.
--- @param suffix string Command suffix after the faction alias.
--- @return boolean matches True when the command matches.
local function matchesMGCommand(lower, suffix)
    return lower == "luamg " .. suffix
        or lower == "luamagesguild " .. suffix
        or lower == "luamages guild " .. suffix
end

local function onConsoleCommand(mode, command)
    local normalized = utils.normalizeConsoleCommand(command)
    local lower = normalized:lower()

    if matchesMGCommand(lower, "cartography dump") then
        local count = getVisitedCount()
        if count == 0 then
            print("MG Cartography: No Places of Power stored.")
            return
        end
        print("MG Cartography: Stored Places of Power (" .. count .. " total):")
        local i = 0
        for cellId, cellName in pairs(visited) do
            i = i + 1
            print("  [" .. i .. "] Name: '" .. tostring(cellName)
                .. "'  |  ID: " .. tostring(cellId))
        end
        print("  appliedResist = " .. appliedResist
            .. " | appliedDetect = " .. appliedDetect
            .. " | appliedMagickaMod = " .. appliedMagickaMod)

    elseif matchesMGCommand(lower, "cartography clear") then
        removeCartographyEffects()
        visited       = {}
        appliedResist = 0
        appliedDetect = 0
        print("MG Cartography: Visited table cleared. All bonuses reversed.")
        ui.showMessage("Magical Cartography data cleared.")

    elseif matchesMGCommand(lower, "debug") then
        local cell = self.cell
        local cellName = cell and cell.name or nil
        local cellId = cell and cell.id or nil
        local ownedRank = getMGRank()
        local s = types.Actor.stats.dynamic.magicka(self)
        print("MG owned rank = " .. tostring(ownedRank))
        print("MG owns: P1=" .. tostring(interfaces.ErnPerkFramework.playerHasPerk(mg1_id))
            .. " P2=" .. tostring(interfaces.ErnPerkFramework.playerHasPerk(mg2_id))
            .. " P3=" .. tostring(interfaces.ErnPerkFramework.playerHasPerk(mg3_id))
            .. " P4=" .. tostring(interfaces.ErnPerkFramework.playerHasPerk(mg4_id)))
        print("MG hasMGCartography = " .. tostring(hasMGCartography))
        print("MG appliedMagickaMod = " .. tostring(appliedMagickaMod))
        print("MG expectedMagickaMod = " .. tostring(MAGICKA_MOD_BY_RANK[ownedRank] or 0))
        print("Magicka: base=" .. s.base .. " modifier=" .. s.modifier .. " current=" .. s.current)
        print("MG Cartography: appliedResist=" .. appliedResist .. " appliedDetect=" .. appliedDetect)
        print("Visited count: " .. getVisitedCount())
        print("Current cell name: " .. tostring(cellName))
        print("Current cell id: " .. tostring(cellId))
        print("Current cell is Place of Power: " .. tostring(isPlaceOfPower(cellName, cellId)))

    elseif lower == "luamg" or lower == "luamg cartography"
        or lower == "luamagesguild" or lower == "luamagesguild cartography"
        or lower == "luamages guild" or lower == "luamages guild cartography" then
        print("MG commands:")
        print("  luamg cartography dump")
        print("  luamg cartography clear")
        print("  luamg debug")
    end
end

-- ============================================================
--  MAGES GUILD PERKS
-- ============================================================

interfaces.ErnPerkFramework.registerPerk({
    id = mg1_id,
    localizedName = "Guild Initiate",
    category = {"FactionPerks", "Imperial Factions", "Mage's Guild", 1},
    localizedFlavour = "You have passed the Guild's entrance rites. "
        .. "The library shelves are open to you.",
    localizedDescription = "Grants the following stats: (+3 Intelligence, +3 Willpower, "
        .. "+10 Fortify Magicka, +5 Destruction, +5 Alteration)",
    hidden = perkHidden(GUILD, 0, 1),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(1) end,
    requirements = {
        FactionGroupRank("magesGuild",0),
        R.minimumLevel(1)
    },
    onAdd    = function()
        applyMGRank(1, "mg1 onAdd")
        end,
    onRemove = function()
        applyMGRank(0, "mg1 onRemove")
        end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = mg2_id,
    localizedName = "Scholastic Rigour",
    category = {"FactionPerks", "Imperial Factions", "Mage's Guild", 2},
    localizedFlavour = "The Guild's structured study has sharpened your mind. "
        .. "You have learned to identify and catalogue the Places of Power "
        .. "that saturate Vvardenfell, drawing knowledge and resistance from each.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+5 Intelligence, +5 Willpower, "
        .. "+20 Fortify Magicka, +10 Destruction, +10 Alteration)\f"
        .. "Effect 2: \n Magical Cartography: Visiting Places of Power grants +1 Resist Magicka "
        .. "and +2 Detect Enchantment per location. Every 10 locations grants a 5% magicka refund "
        .. "on successful spell casts (max 25%).",
    hidden = perkHidden(GUILD, 3, 5),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(2) end,
    requirements = {
        R.hasPerk(mg1_id),
        FactionGroupRank("magesGuild",3),
        R.minimumAttributeLevel('intelligence', 40),
        R.minimumLevel(5),
    },
    onAdd = function()
        applyMGRank(2, "mg2 onAdd")
    end,
    onRemove = function()
        applyMGRank(0, "mg2 onRemove")
    end,
})

interfaces.ErnPerkFramework.registerPerk({
    id = mg3_id,
    localizedName = "Arcane Reservoir",
    category = {"FactionPerks", "Imperial Factions", "Mage's Guild", 3},
    localizedFlavour = "Years of disciplined spellcasting have deepened your reserves. "
        .. "Your magicka pool expands with your intellect.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+10 Intelligence, +10 Willpower, "
        .. "+35 Fortify Magicka, +18 Destruction, +18 Alteration)\f"
        .. "Effect 2: \n Fortify Maximum Magicka by 0.5x Intelligence.",
    hidden = perkHidden(GUILD, 6, 10),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(3) end,
    requirements = {
        R.hasPerk(mg2_id),
        FactionGroupRank("magesGuild",6),
        R.minimumAttributeLevel('intelligence', 50),
        R.minimumLevel(10),
    },
    onAdd    = function()
        applyMGRank(3, "mg3 onAdd")
        end,
    onRemove = function()
        applyMGRank(0, "mg3 onRemove")
        end,
})


interfaces.ErnPerkFramework.registerPerk({
    id = mg4_id,
    localizedName = "Archmagister's Peer",
    category = {"FactionPerks", "Imperial Factions", "Mage's Guild", 4},
    localizedFlavour = "The senior mages regard you as a genuine equal. "
        .. "Your intellect feeds your power directly.",
    localizedDescription = "Effect 1: \n Grants the following stats: (+15 Intelligence, +15 Willpower, "
        .. "+50 Fortify Magicka, +25 Destruction, +25 Alteration)\f"
        .. "Effect 2: \n Fortify Maximum Magicka by 1.0x Intelligence "
        .. "(replaces Arcane Reservoir's 0.5x bonus).",
    hidden = utils.leaderTrainingHidden("magesGuild", perkHidden(GUILD, 9, 15)),
    art = "textures\\levelup\\mage",
    cost = function() return utils.perkCost(4) end,
    requirements = {
        utils.leaderTrainingRequirement("magesGuild"),
        utils.leaderTrainingRankRequirement("magesGuild", 9),
        R.hasPerk(mg3_id),
        FactionGroupRank("magesGuild",9),
        R.minimumAttributeLevel('intelligence', 75),
        R.minimumLevel(15),
    },
    onAdd    = function()
        applyMGRank(4, "mg4 onAdd")
        end,
    onRemove = function()
        applyMGRank(0, "mg4 onRemove")
        end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================

local function onUpdate(dt)
    reconcileOwnedMGRank("onUpdate")
    if not hasMGCartography then return end

    cellCheckTimer = cellCheckTimer - dt
    if cellCheckTimer > 0 then return end
    cellCheckTimer = CELL_CHECK_INTERVAL

    local cell = self.cell
    if not cell then
        lastCellId = nil
        return
    end

    local cellId = cell.id
    if cellId == lastCellId then return end
    lastCellId = cellId

    checkCurrentCell(cell)
end

local function onSave()
    return {
        appliedMagickaMod = appliedMagickaMod,
        appliedResist     = appliedResist,
        appliedDetect     = appliedDetect,
        visited           = visited,
        appliedStats      = appliedStats
    }
end

local function onLoad(data)
    data              = data or {}
    appliedMagickaMod = data.appliedMagickaMod or 0
    appliedResist     = data.appliedResist     or 0
    appliedDetect     = data.appliedDetect     or 0
    visited           = data.visited           or {}
    lastCellId        = nil
    cellCheckTimer    = 0
    lastAppliedMGRank = nil
    utils.debug(1, "MG", "Cartography loaded " .. getVisitedCount()
        .. " Places of Power from save.")
    -- Reverse saved modifiers first so setRank starts from zero
    utils.clearSavedAppliedStats(data.appliedStats, appliedStats)
end

return {
    engineHandlers = {
        onUpdate         = onUpdate,
        onSave           = onSave,
        onLoad           = onLoad,
        onConsoleCommand = onConsoleCommand,
    },
}
