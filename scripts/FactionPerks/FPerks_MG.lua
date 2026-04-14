--[[
    MG:
        FPerks_MG1_Passive          - +5 Intelligence, +10 Fortify Magicka
        FPerks_MG2_Passive          - +15 Intelligence, +25 Fortify Magicka
        FPerks_MG3_Passive          - +25 Intelligence, +50 Fortify Magicka,
                                      Fortify Maximum Magicka 0.5x Intelligence (magnitude 5)
        FPerks_MG4_Passive          - +25 Willpower, +75 Fortify Magicka,
                                      Fortify Maximum Magicka 1.0x Intelligence (magnitude 10)

    Magical Cartography (P2+):
        Visiting Places of Power builds two scaling bonuses:
            Per location visited:    +1 Resist Magicka, +2 Detect Enchantment
            Per 10 locations:        +5% magicka refund on successful spell cast (max 25%)

        Places of Power:
            Daedric Inner Shrines   (cell name contains "inner shrine")
            Propylon Chambers       (cell name contains "propylon chamber")
            Unique locations:
                Mount Kand
                Akulakhan's Chamber
                Palace of Vivec
                Ministry of Truth
                High Palace

        Visited locations are stored permanently in player storage -
        exploration is never lost. Bonuses only apply while the perk
        is held. If the perk is lost and regained, the full count
        is restored immediately.

        Spell refund detection uses the AnimationController text key
        pattern from the Incantation mod to track cast start, and
        SkillProgression to confirm the cast succeeded before applying
        the refund.

    NOTE: If Detect Enchantment does not apply without a base active
    effect present, add a base ESP ability "FPerks_MG2_Cartography"
    with Detect Enchantment magnitude 1 and Resist Magicka magnitude 1,
    granted in mg2 onAdd alongside setRank(2).
]]

local ns          = require("scripts.FactionPerks.namespace")
local utils       = require("scripts.FactionPerks.utils")
local notExpelled = utils.notExpelled
local interfaces  = require("openmw.interfaces")
local types       = require('openmw.types')
local self        = require('openmw.self')
local core        = require('openmw.core')
local ui          = require('openmw.ui')
local storage     = require('openmw.storage')

local R = interfaces.ErnPerkFramework.requirements

local perkTable = {
    [1] = { passive = {"FPerks_MG1_Passive"} },
    [2] = { passive = {"FPerks_MG2_Passive"} },
    [3] = { passive = {"FPerks_MG3_Passive"} },
    [4] = { passive = {"FPerks_MG4_Passive"} },
}

local setRank = utils.makeSetRank(perkTable, nil)

-- ============================================================
--  MAGICAL CARTOGRAPHY - Scholastic Rigour (P2+)
--
--  Tracks Places of Power the player enters. Each new location
--  grants +1 Resist Magicka and +2 Detect Enchantment via
--  delta-based activeEffects:modify. Every 10 locations adds
--  a further 5% magicka refund on successful spell casts,
--  capped at 25% at 50 locations.
--
--  Storage is permanent - the visited set survives respecs.
--  Session trackers (appliedResist, appliedDetect) reset on
--  each load so onAdd always applies from a clean baseline.
-- ============================================================

-- Permanent storage for discovered cell IDs
local cartographyStore = storage.playerSection("FactionPerks_MG_Cartography")

-- Session state - not persisted, recalculated from storage on load
local hasMGCartography = false
local appliedResist    = 0    -- total Resist Magicka we've applied via modify this session
local appliedDetect    = 0    -- total Detect Enchantment we've applied via modify this session
local castedSpell      = nil  -- spell selected at cast animation start
local lastCastCost     = 0    -- cost of that spell, cached before the cast deducts it
local lastCellId       = nil  -- tracks cell changes to avoid redundant checks
local cellCheckTimer   = 0
local CELL_CHECK_INTERVAL = 2.0  -- seconds between cell checks

-- ============================================================
--  LOCATION DETECTION
-- ============================================================

local UNIQUE_LOCATIONS = {
    ["mount kand"]          = true,
    ["akulakhan's chamber"] = true,
    ["palace of vivec"]     = true,
    ["ministry of truth"]   = true,
    ["high palace"]         = true,
}

local function isPlaceOfPower(cellName)
    local lower = cellName:lower()
    -- Daedric Inner Shrines
    if lower:find("inner shrine",    1, true) then return true end
    -- Propylon Chambers
    if lower:find("propylon chamber", 1, true) then return true end
    -- Curated unique locations - exact case-insensitive match to avoid false positives
    if UNIQUE_LOCATIONS[lower]                 then return true end
    return false
end

-- ============================================================
--  VISITED COUNT AND REFUND CALCULATION
-- ============================================================

local function getVisitedCount()
    local visited = cartographyStore:get("visited")
    if not visited then return 0 end
    local count = 0
    for _ in pairs(visited) do count = count + 1 end
    return count
end

local function getRefundPercent(count)
    -- 5% per 10 locations, capped at 25% at 50 locations
    return math.min(math.floor(count / 10) * 0.05, 0.25)
end

-- ============================================================
--  EFFECT APPLICATION
--  Delta-based: tracks what has been applied this session and
--  only calls modify with the difference. This means:
--    - onAdd can safely call applyCartographyEffects(count)
--      without double-applying if called multiple times.
--    - removeCartographyEffects() calls applyCartographyEffects(0)
--      which reverses the full applied amount cleanly.
-- ============================================================

local function applyCartographyEffects(count)
    local activeEffects = types.Actor.activeEffects(self)

    local targetResist = count        -- +1 per location
    local targetDetect = count * 2    -- +2 per location

    local deltaResist = targetResist - appliedResist
    local deltaDetect = targetDetect - appliedDetect

    if deltaResist ~= 0 then
        activeEffects:modify(deltaResist, "resistmagicka")
        appliedResist = targetResist
    end
    if deltaDetect ~= 0 then
        -- NOTE: If Detect Enchantment does not work without a base
        -- active effect, add "FPerks_MG2_Cartography" ESP ability
        -- in mg2 onAdd as an anchor for this modify call.
        activeEffects:modify(deltaDetect, "detectenchantment")
        appliedDetect = targetDetect
    end
end

local function removeCartographyEffects()
    -- Passing 0 causes applyCartographyEffects to apply the full
    -- negative delta, reversing everything applied this session.
    applyCartographyEffects(0)
end

-- ============================================================
--  CELL DISCOVERY
--  Called when the player enters a new interior cell.
--  Stores the cell ID permanently and updates effects.
-- ============================================================

local function checkCurrentCell()
    if not hasMGCartography then return end
    local cell = self.cell
    if not cell or cell.isExterior then return end

    local cellName = cell.name or ""
    if not isPlaceOfPower(cellName) then return end

    local cellId  = cell.id
    local visited = cartographyStore:get("visited") or {}
    if visited[cellId] then return end  -- already catalogued, nothing to do

    -- New Place of Power discovered
    local oldCount = getVisitedCount()
    visited[cellId] = cellName  -- store name for readability if inspected
    cartographyStore:set("visited", visited)
    local newCount = oldCount + 1

    applyCartographyEffects(newCount)

    -- Show milestone message if a new refund tier was crossed,
    -- otherwise show a quieter discovery confirmation.
    local oldMilestone = math.floor(oldCount / 10)
    local newMilestone = math.floor(newCount / 10)

    if newMilestone > oldMilestone and newMilestone <= 5 then
        local refundPct = newMilestone * 5
        ui.showMessage("Magical Cartography: " .. newCount
            .. " Places of Power catalogued. Spell refund: "
            .. refundPct .. "%.")
    else
        ui.showMessage("Magical Cartography: Place of Power catalogued. ("
            .. newCount .. " total)")
    end

    print("MG Cartography: Discovered '" .. cellName
        .. "' (total: " .. newCount .. ")")
end

-- ============================================================
--  SPELL CAST TRACKING
--  AnimationController text key fires at the start of the cast
--  animation. We cache the selected spell and its cost here.
--  The cost must be read before the engine deducts it.
-- ============================================================

interfaces.AnimationController.addTextKeyHandler('', function(groupname, key)
    if groupname ~= "spellcast" then return end
    if key == "self start" or key == "touch start" or key == "target start" then
        castedSpell  = types.Player.getSelectedSpell(self)
        lastCastCost = castedSpell and castedSpell.cost or 0
    elseif key == "self stop" or key == "touch stop" or key == "target stop" then
        -- Clear after the cast animation completes whether it succeeded or not.
        -- SkillProgression fires before stop, so the refund is already applied.
        castedSpell  = nil
        lastCastCost = 0
    end
end)

-- ============================================================
--  MAGICKA REFUND ON SUCCESSFUL CAST
--  SkillProgression.addSkillUsedHandler fires only when a magic
--  school skill advances - this happens only on successful casts.
--  This is our reliable success gate, consistent with Incantation.
-- ============================================================

local MAGIC_SKILLS = {
    destruction = true,
    restoration = true,
    conjuration = true,
    mysticism   = true,
    illusion    = true,
    alteration  = true,
}

interfaces.SkillProgression.addSkillUsedHandler(function(skillId, params)
    if not hasMGCartography                  then return end
    if not MAGIC_SKILLS[skillId]             then return end
    if not castedSpell or lastCastCost <= 0  then return end

    local count         = getVisitedCount()
    local refundPercent = getRefundPercent(count)
    if refundPercent <= 0 then return end

    local refundAmount = math.floor(lastCastCost * refundPercent)
    if refundAmount <= 0 then return end

    local magicka    = types.Actor.stats.dynamic.magicka(self)
    local maxMagicka = magicka.base + magicka.modifier
    magicka.current  = math.min(magicka.current + refundAmount, maxMagicka)

    print("MG Cartography: Refunded " .. refundAmount
        .. " magicka (" .. (refundPercent * 100) .. "% of " .. lastCastCost .. ")")
end)

-- ============================================================
--  MAGES GUILD PERKS
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
        R().minimumLevel(1)
    },
    onAdd    = function() setRank(1) end,
    onRemove = function() setRank(nil) end,
})

local mg2_id = ns .. "_mg_scholastic_rigour"
interfaces.ErnPerkFramework.registerPerk({
    id = mg2_id,
    localizedName = "Scholastic Rigour",
    --hidden = true,
    localizedDescription = "The Guild's structured study has sharpened your mind. "
        .. "You have learned to identify and catalogue the Places of Power "
        .. "that saturate Vvardenfell, drawing knowledge and resistance from each.\n "
        .. "Requires Guild Initiate. "
        .. "(+15 Intelligence, +25 Fortify Magicka)\n\n"
        .. "Magical Cartography: Visiting Places of Power grants +1 Resist Magicka "
        .. "and +2 Detect Enchantment per location. Every 10 locations grants "
        .. "a 5%% magicka refund on successful spell casts (max 25%%).",
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(mg1_id),
        R().minimumFactionRank('mages guild', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        setRank(2)
        hasMGCartography = true
        -- Reset session trackers so applyCartographyEffects starts
        -- from a clean baseline, even if called multiple times
        -- (e.g. respec then re-take).
        appliedResist    = 0
        appliedDetect    = 0
        -- Immediately apply bonuses for all previously visited locations.
        applyCartographyEffects(getVisitedCount())
    end,
    onRemove = function()
        setRank(nil)
        hasMGCartography = false
        removeCartographyEffects()
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
    onAdd    = function() setRank(3) end,
    onRemove = function() setRank(nil) end,
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
        .. "Fortify Maximum Magicka 1.0x Intelligence "
        .. "[replaces Arcane Reservoir's 0.5x bonus])",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(mg3_id),
        R().minimumFactionRank('mages guild', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd    = function() setRank(4) end,
    onRemove = function() setRank(nil) end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================

local function onUpdate(dt)
    if not hasMGCartography then return end

    cellCheckTimer = cellCheckTimer - dt
    if cellCheckTimer > 0 then return end
    cellCheckTimer = CELL_CHECK_INTERVAL

    local cell = self.cell
    if not cell or cell.isExterior then
        lastCellId = nil
        return
    end

    -- Only run the full check when the cell has actually changed
    local cellId = cell.id
    if cellId == lastCellId then return end
    lastCellId = cellId

    checkCurrentCell()
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
}