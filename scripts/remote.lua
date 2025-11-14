local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local graph = require("scripts.graph")
local main = require("scripts.main")
local saving = require("scripts.saving")
local production = require("scripts.production")

local prefix = commons.prefix

---@param player_index integer
---@param remoteConfig RemoteConfig
local function add_recipes(player_index, remoteConfig)
    local player = game.players[player_index]

    main.enter(player)

    if not remoteConfig.recipes then
        return
    end

    local g = gutils.get_graph(player)
    for name, recipe in pairs(remoteConfig.recipes) do
        local grecipe = g.recipes[name]
        if grecipe then
            g.selection[name] = grecipe
        end
    end
    graph.refresh(player)
    gutils.fire_selection_change(g)
end

---@param player_index integer
local function get_ingredients(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)
    if not g then return nil end

    local product_outputs = g.product_outputs or {}
    local product_inputs = g.product_inputs or {}

    local inputs = gutils.get_product_flow(g, g.selection)
    if not inputs then return nil end

    local result = {}
    for product_name, _ in pairs(inputs) do
        output = product_outputs[product_name] or 0
        input = product_inputs[product_name] or 0
        local amount = input - output
        if amount > 0 then
            result[product_name] = amount
        end
    end
    return result
end

---@param player_index integer
local function get_outputs(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)
    if not g then return nil end

    local result = {}
    for name, value in pairs(g.iovalues) do
        if type(value) == "number" and value > 0 then
            result[name] = value
        end
    end
    return result
end

---@class ExportedMachine
---@field name string
---@field quality string
---@field count number
---@field modules string[]
---@field beacon_name string
---@field beacon_count integer
---@field beacon_module string[]


---@class ExportedRecipe
---@field name string
---@field machine ExportedMachine


---@class ExportedModule
---@field name string
---@field machine ExportedMachine

---@param player_index integer
---@return ExportedRecipe[]?
local function get_recipes(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)
    if not g then return nil end

    local recipes = production.compute_recipes(g)
    local exports = {}
    for name, recipe in pairs(recipes) do
        if not recipe.is_product then
            local machine = recipe.machine
            ---@type ExportedRecipe
            local exr = {
                name = name,
            }
            if machine then
                exr.machine = {
                    name = machine.name,
                    count = machine.count,
                    quality = machine.machine_quality
                }
                local config = machine.config
                if config then
                    if machine.modules then
                        config.machine_modules = {}
                        for _, m in pairs(machine.machine_modules) do
                            table.insert(config.machine_modules, m.name)
                        end
                    end
                    if config.beacon_name then
                        exr.machine.beacon_name = config.beacon_name
                        exr.machine.beacon_count = config.beacon_count
                        exr.machine.beacon_module = config.beacon_modules
                    end
                end
            end
            table.insert(exports, exr)
        end
    end
    return exports
end

remote.add_interface(prefix, {
    add_recipes = add_recipes,
    get_ingredients = get_ingredients,
    get_recipes = get_recipes,
    get_outputs = get_outputs
})

local default_speed = 4

commands.add_command(prefix .. "_speed", nil, function(command)
    if command.player_index ~= nil then
        local player = game.players[command.player_index]
        local param = command.parameter
        if not param then
            param = tostring(default_speed)
        end

        local speed = tonumber(param)
        if not speed then
            speed = default_speed
        end

        main.set_speed(player, speed)
        player.print("Speed " .. speed)
    end
end)
