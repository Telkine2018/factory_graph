local mod_gui = require("mod-gui")
local dictionary = require("__flib__/dictionary-lite")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local debug = tools.debug
local prefix = commons.prefix

local gutils = require("scripts.gutils")
local graph = require("scripts.graph")
local command = require("scripts.command")
local machinedb = require("scripts.machinedb")
local product_panel = require("scripts.product_panel")

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

---@param player LuaPlayer
local function switch_surface(player)

    if not string.find(player.surface.name, commons.surface_prefix_filter) then
        if player.gui.left[switch_button_name] then
            player.gui.left[switch_button_name].destroy()
        end

        local vars = tools.get_vars(player)
        local surface = main.enter(player)
        if not vars.graph then
            local g = graph.new(surface)
            g.player = player
            vars.graph = g
            local recipes = player.force.recipes
            graph.update_recipes(g, recipes, excluded_categories)
            graph.do_layout(g)
            graph.draw(g)
        end
        command.open(player)
    else
        main.exit(player)
    end
end

---@param e EventData.on_lua_shortcut
local function on_switch_surface(e)
    local player = game.players[e.player_index]
    switch_surface(player)
end

script.on_event(prefix .. "-alt_k", on_switch_surface)
tools.on_gui_click(switch_button_name, on_switch_surface)

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
    local surface_name = surface_prefix .. player.index
    local surface = game.surfaces[surface_name]

    if not surface then
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

        surface = game.create_surface(surface_name, settings)
        surface.map_gen_settings = settings
        surface.daytime = 0
        surface.freeze_daytime = true
        surface.show_clouds = false
    end

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

    local g = gutils.get_graph(player)
    ---@type MapPosition
    local player_position = { 0, 0 }
    if g and g.player_position then
        player_position = g.player_position
    end
    player.teleport(player_position, surface)
    return surface
end

---@param player LuaPlayer
function main.exit(player)
    local vars = tools.get_vars(player)
    local character = vars.character

    if character then
        local g = gutils.get_graph(player)
        g.player_position = player.position
        player.teleport(character.position, character.surface, true)
    end
end

tools.on_event(defines.events.on_player_changed_surface,

    ---@param e EventData.on_player_changed_surface
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)
        if not g then return end

        if e.surface_index == g.surface.index then
            tools.close_panels(player)
            command.close(player)
            local character = vars.character
            if vars.character then
                player.teleport(character.position, character.surface)
                player.associate_character(vars.character)
                player.set_controller { type = defines.controllers.character, character = vars.character }
                vars.character = nil
            end
        end
    end)


---@param player LuaPlayer
local function create_player_button(player)
    local button_flow = mod_gui.get_button_flow(player)
    local button_name = prefix .. "_switch"
    if button_flow[button_name] then
        button_flow[button_name].destroy()
    end
    if not button_flow[button_name] then
        local button = button_flow.add {
            type = "sprite-button",
            name = button_name,
            sprite = prefix .. "_switch"
        }
        button.style.width = 40
        button.style.height = 40
    end
end

tools.on_gui_click(prefix .. "_switch", 

---@param e EventData.on_gui_click
function(e)
    if not e.shift and not e.alt and not e.control then
        switch_surface(game.players[e.player_index])
    elseif e.control then
        product_panel.create(e.player_index)
    end
end)

tools.on_configuration_changed(function(data)
    for _, player in pairs(game.players) do

        create_player_button(player)

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
