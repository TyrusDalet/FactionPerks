--[[
    FactionPerks settings.lua

    Registers the mod settings page and exposes the current values.
]]

local interfaces = require("openmw.interfaces")
local storage = require("openmw.storage")
local MOD_NAME = require("scripts.FactionPerks.namespace")

local SECTION = "Settings" .. MOD_NAME

local DEFAULTS = {
    perkVisibilityMode = 3,
    perkCostMode = 1,
    perkRequirementMode = 1,
}

local function init()

    interfaces.Settings.registerPage {
        key = MOD_NAME,
        l10n = MOD_NAME,
        name = "name",
    }

    interfaces.Settings.registerGroup {
        key = SECTION,
        page = MOD_NAME,
        l10n = MOD_NAME,
        name = "settings",
        permanentStorage = true,
        settings = {
            {
                key = "perkVisibilityMode",
                name = "perkVisibilityModeName",
                description = "perkVisibilityModeDescription",
                default = DEFAULTS.perkVisibilityMode,
                renderer = "number",
                argument = {
                    integer = true,
                    min = 1,
                    max = 4,
                },
            },
            {
                key = "perkCostMode",
                name = "perkCostModeName",
                description = "perkCostModeDescription",
                default = DEFAULTS.perkCostMode,
                renderer = "number",
                argument = {
                    integer = true,
                    min = 1,
                    max = 3,
                },
            },
            {
                key = "perkRequirementMode",
                name = "perkRequirementModeName",
                description = "perkRequirementModeDescription",
                default = DEFAULTS.perkRequirementMode,
                renderer = "number",
                argument = {
                    integer = true,
                    min = 1,
                    max = 4,
                },
            },
        },
    }
end

local section = storage.playerSection(SECTION)

local lookup = {
    __index = function(tbl, key)
        if key == "init" then
            return init
        elseif key == "MOD_NAME" then
            return MOD_NAME
        elseif DEFAULTS[key] ~= nil then
            local val = tbl.section:get(key)
            if val ~= nil then
                return val
            end
            return DEFAULTS[key]
        end

        local val = tbl.section:get(key)
        if val ~= nil then
            return val
        end
        error("unknown setting " .. tostring(key))
    end,
}

local container = {
    section = section,
}
setmetatable(container, lookup)

return container
