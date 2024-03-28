
local dictionary = require("__flib__/dictionary-lite")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local debug = tools.debug
local prefix = commons.prefix

local graph = require("scripts.graph")
local command = require("scripts.command")
local machinedb = require("scripts.machinedb")

local main = {}

local surface_prefix = commons.surface_prefix
local recipe_symbol_name = prefix .. "-recipe-symbol"

local switch_button_name = prefix .. "-switch"

local excluded_categories = {

     stacking = true, 
     unstacking = true,
     barrelling = true,
     ["barreling-pump"] = true,
     
     -- Creative mod
    ["creative-mod_free-fluids"] = true,
    ["creative-mod_energy-absorption"] = true,

    -- Editor extensions
    ["ee-testing-tool"] = true,

    -- Deep storage unit
    ["deep-storage-item"] = true,
    ["deep-storage-fluid"] = true,
    ["deep-storage-item-big"] = true,
    ["deep-storage-fluid-big"] = true,
    ["deep-storage-item-mk2/3"] = true,
    ["deep-storage-fluid-mk2/3"] = true,

    -- Krastorio 2
    ["void-crushing"] = true, -- This doesn't actually exist yet, but will soon!
    -- Mining drones
    ["mining-depot"] = true,
        -- Pyanodon's
    ["py-incineration"] = true,
    ["py-runoff"] = true,
    ["py-venting"] = true,
    -- Reverse factory
    ["recycle-intermediates"] = true,
    ["recycle-productivity"] = true,
    ["recycle-products"] = true,
    ["recycle-with-fluids"] = true,
    -- Transport drones
    ["fuel-depot"] = true,
    ["transport-drone-request"] = true,
    ["transport-fluid-request"] = true,
    
}

---@param e EventData.on_lua_shortcut
local function switch_surface(e)
    local player = game.players[e.player_index]
    local character = player.character

    if not string.match(player.surface.name, commons.surface_prefix_filter) then

        if not player.gui.left[switch_button_name] then
            player.gui.left.add {type="button", name=switch_button_name, caption="Grapher"}
        end

        local surface = main.enter(player)
        local g = graph.new(surface)
        g.player = player
        tools.get_vars(player).graph = g
        local recipes = player.force.recipes
        graph.add_recipes(g, recipes, excluded_categories)
        graph.do_layout(g)
        graph.draw(g)
        command.open(player)
    else
        main.exit(player)
    end
end
script.on_event(prefix .. "-alt_k", switch_surface)

tools.on_gui_click(switch_button_name, switch_surface)

---@param e EventData.on_lua_shortcut
local function test_click(e)
    local player = game.players[e.player_index]
    local surface = player.surface

    if string.sub(surface.name, 1, #surface_prefix) ~= surface_prefix then
        return
    end

    -- player.print("test_click:" .. game.tick)
end
script.on_event(prefix .. "-click", test_click)

local tile_name = commons.tile_name

---@param player LuaPlayer
---@return LuaSurface
function main.enter(player)
    local vars = tools.get_vars(player)

    if not game.tile_prototypes[tile_name] then
        tile_name = "lab-dark-2"
    end

    local settings = {
        height = 1000,
        width = 1000,
        autoplace_controls = {},
        default_enable_all_autoplace_controls = false,
        cliff_settings = { cliff_elevation_0 = 1024 },
        starting_area = "none",
        starting_points = {},
        terrain_segmentation = "none",
        autoplace_settings = {
            entity = { treat_missing_as_default = false, frequency = "none" },
            tile = {
                treat_missing_as_default = false,
                settings = {
                    [tile_name] = {
                        frequency = 6,
                        size = 6,
                        richness = 6
                    }
                }
            },
            decorative = { treat_missing_as_default = false, frequency = "none" }
        },
        property_expression_names = {
            cliffiness = 0,
            ["tile:water:probability"] = -1000,
            ["tile:deep-water:probability"] = -1000,
            ["tile:" .. tile_name .. ":probability"] = "inf"
        }
    }

    local surface = game.create_surface(surface_prefix .. player.index, settings)
    surface.map_gen_settings = settings
    surface.daytime = 0
    surface.freeze_daytime = true
    surface.show_clouds = false

    local character = player.character
    vars.character = character
    vars.surface = surface
    ---@cast character -nil
    player.disassociate_character(character)
    local controller_type
    controller_type = defines.controllers.ghost
    controller_type = defines.controllers.spectator
    controller_type = defines.controllers.god
    player.set_controller { type = controller_type }
    player.teleport({ 0, 0 }, surface)
    return surface
end

---@param player LuaPlayer
function main.exit(player)
    local vars = tools.get_vars(player)

    tools.close_panels(player)
    local character = vars.character
    player.teleport(character.position, character.surface)
    player.associate_character(vars.character)
    player.set_controller { type = defines.controllers.character, character = vars.character }
    game.delete_surface(vars.surface)
    command.close(player)
    vars.graph = nil
end


tools.on_configuration_changed(function(data)
    for _, player in pairs(game.players) do
        ---@type Graph
        local g = tools.get_vars(player).graph
        if g then
            if not g.grid_size then
                g.grid_size = commons.grid_size
            end
            if not g.color_index then
                g.color_index = 0
            end
            local has_command = player.gui.left[command.frame_name] ~= nil
            tools.close_panels(player)
            if has_command then
                command.open(player)
            end
            local recipes = player.force.recipes
            for _, grecipe in pairs(g.recipes) do
                local r = recipes[grecipe.name]
                if r then
                    grecipe.enabled = r.enabled
                else
                    grecipe.enabled = true
                end
                if not grecipe.order then
                    grecipe.order = 1
                end
            end
        end
    end
end)

return main

