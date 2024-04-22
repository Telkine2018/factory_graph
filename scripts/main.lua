local mod_gui = require("mod-gui")
local dictionary = require("__flib__/dictionary-lite")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local debug = tools.debug
local prefix = commons.prefix

local gutils = require("scripts.gutils")
local graph = require("scripts.graph")
local drawing = require("scripts.drawing")
local command = require("scripts.command")
local machinedb = require("scripts.machinedb")
local product_panel = require("scripts.product_panel")
local saving = require("scripts.saving")

local main = {}

local surface_prefix = commons.surface_prefix
local recipe_symbol_name = prefix .. "-recipe-symbol"

local switch_button_name = prefix .. "-switch"

local function np(name)
    return prefix .. "-main." .. name
end


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

---@param player any
function main.enter(player)
    if string.find(player.surface.name, commons.surface_prefix_filter) then
        return
    end
    if player.gui.left[switch_button_name] then
        player.gui.left[switch_button_name].destroy()
    end

    local vars = tools.get_vars(player)
    local surface = main.enter_surface(player)
    if not vars.graph then
        local g = graph.new(surface)
        g.player = player
        vars.graph = g
        local recipes = player.force.recipes
        graph.update_recipes(g, recipes, excluded_categories)
        graph.do_layout(g)
        graph.create_recipe_objects(g)
    end
    command.open(player)
end

---@param player LuaPlayer
local function switch_surface(player)
    if not string.find(player.surface.name, commons.surface_prefix_filter) then
        main.enter(player)
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

---@param e EventData.on_gui_click
function on_switch_click(e)
    if e.button == defines.mouse_button_type.left then
        local player = game.players[e.player_index]
        if not (e.button ~= defines.mouse_button_type.left or e.control or e.shift or e.alt) then
            switch_surface(player)
        elseif not (e.button ~= defines.mouse_button_type.left or not e.control or e.shift or e.alt) then
            player.cursor_stack.clear()
            player.cursor_stack.set_stack(prefix .. "-selection_tool")
        elseif not (e.button ~= defines.mouse_button_type.left or e.control or not e.shift or e.alt) then
            local g = gutils.get_graph(player)
            if not g then return end
            product_panel.create(e.player_index)
        elseif not (e.button ~= defines.mouse_button_type.left or e.control or e.shift or not e.alt) then

            local vars = tools.get_vars(player)
            if vars.saved_character then
                vars.character = vars.saved_character
            end
            switch_surface(player)
        end
    end
end

tools.on_gui_click(prefix .. "_switch", on_switch_click)


local tile_name = commons.tile_name

---@param player LuaPlayer
---@return LuaSurface
function main.enter_surface(player)
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
    vars.surface = surface
    vars.extern_surface = player.surface
    vars.extern_position = player.position
    if character then
        vars.character = character
        player.disassociate_character(character)
    end
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
        local zoom = g.graph_zoom_level
        if zoom then
            if zoom < 0.2 then
                zoom = 0.2
            elseif zoom > 5 then
                zoom = 5
            end
            player.zoom = zoom
        end
    end
    player.teleport(player_position, surface, false)
    return surface
end

---@param player LuaPlayer
function main.exit(player)
    local vars = tools.get_vars(player)
    local g = gutils.get_graph(player)

    if not g then return end
    if g.surface.index ~= player.surface_index then return end

    local extern_position = vars.extern_position
    if not extern_position and vars.character then
        extern_position = vars.character.position
    end

    local zoom = g.world_zoom_level
    if zoom then
        if zoom < 0.2 then
            zoom = 0.2
        elseif zoom > 5 then
            zoom = 5
        end
        player.zoom = zoom
    end

    local character = vars.character
    if character and character.valid then
        player.teleport(character.position, character.surface, false)
        player.associate_character(vars.character)
        player.set_controller { type = defines.controllers.character, character = vars.character }
        character.cheat_mode = false
        vars.character = nil
    elseif vars.extern_position and vars.extern_surface then
        player.teleport(vars.extern_position, vars.extern_surface, false)
    elseif vars.extern_position then
        player.teleport(vars.extern_position, "Nauvis", false)
    elseif vars.extern_position then
        player.teleport({ 0, 0 }, "Nauvis", false)
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
        end
    end)

tools.on_event(defines.events.on_player_changed_position,
    ---@param e EventData.on_player_changed_position
    function(e)
        local player = game.players[e.player_index]
        local character = player.character
        if not character then return end

        local vars = tools.get_vars(player)
        vars.saved_character = character
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
            sprite = prefix .. "_switch",
            tooltip = { np("switch_tooltip") }
        }
        button.style.width = 40
        button.style.height = 40
    end
end

local function picker_dolly_install()
    if remote.interfaces["PickerDollies"] then
        remote.call("PickerDollies", "add_blacklist_name", commons.recipe_symbol_name)
        remote.call("PickerDollies", "add_blacklist_name", commons.unresearched_symbol_name)
        remote.call("PickerDollies", "add_blacklist_name", commons.product_symbol_name)
        remote.call("PickerDollies", "add_blacklist_name", commons.product_selector_name)
    end
end

tools.on_init(function()
    picker_dolly_install()
end)

tools.on_event(defines.events.on_player_created,
    ---@param e EventData.on_player_created
    function(e)
        local player = game.players[e.player_index]
        create_player_button(player)
    end)

tools.on_configuration_changed(function(data)
    picker_dolly_install()
    for _, player in pairs(game.players) do
        create_player_button(player)

        local vars = tools.get_vars(player)
        if vars.character_speed then
            main.set_speed(player, true)
        end

        ---@type Graph
        local g = vars.graph
        if g then
            if not g.grid_size then
                g.grid_size = commons.grid_size
            end
            if not g.color_index then
                g.color_index = 0
            end
            local has_command = player.gui.left[command.frame_name] ~= nil
            tools.close_panels(player)
            tools.close_panel(player, prefix .. "-product-panel.frame")
            if has_command then
                command.open(player)
            end
            local recipes = player.force.recipes
            graph.update_recipes(g, recipes, g.excluded_categories)

            local need_refresh
            for _, grecipe in pairs(g.recipes) do
                if grecipe.visible and (not grecipe.line and not grecipe.col) then
                    need_refresh = true
                    break
                end
            end

            graph.deferred_update(player, { selection_changed = true, do_layout = need_refresh })
        end
    end
end)

tools.on_load(function()
    picker_dolly_install()
end)

tools.on_event(defines.events.on_research_finished,
    ---@param e EventData.on_research_finished
    function(e)
        local tech = e.research
        local force_index = tech.force.index

        for _, player in pairs(game.players) do
            if player.force_index == force_index then
                local g = gutils.get_graph(player)
                if g then
                    local need_refresh
                    for _, effect in pairs(tech.effects) do
                        if effect.type == "unlock-recipe" then
                            local recipe_name = effect.recipe
                            local grecipe = g.recipes[recipe_name]
                            if grecipe then
                                grecipe.enabled = true
                                if grecipe.visible then
                                    need_refresh = true
                                end
                            end
                        end
                    end
                    if need_refresh then
                        graph.refresh(player, true)
                    end
                end
            end
        end
    end
)

tools.on_event(defines.events.on_research_reversed,
    ---@param e EventData.on_research_reversed
    function(e)
        local tech = e.research
        local force_index = tech.force.index

        for _, player in pairs(game.players) do
            if player.force_index == force_index then
                local g = gutils.get_graph(player)
                if g then
                    local need_refresh
                    for _, effect in pairs(tech.effects) do
                        if effect.type == "unlock-recipe" then
                            local recipe_name = effect.recipe
                            local grecipe = g.recipes[recipe_name]
                            if grecipe then
                                grecipe.enabled = false
                                if grecipe.visible then
                                    need_refresh = true
                                end
                            end
                        end
                    end
                    if need_refresh then
                        graph.refresh(player, true)
                    end
                end
            end
        end
    end
)

---@param e EventData.on_player_selected_area
local function import_entities(e, clear)
    local player = game.players[e.player_index]
    if string.find(player.surface.name, commons.surface_prefix_filter) then
        return
    end

    if e.item ~= prefix .. "-selection_tool" then return end

    local g = gutils.get_graph(player)
    if not g then
        main.enter(player)
        g = gutils.get_graph(player)
    end

    if g.visibility == commons.visibility_all then
        g.visibility = commons.visibility_selection
        command.update_display(player)
    end

    if clear then
        gutils.clear(g)
        g.selection = {}
        saving.clear_current(player)
    end
    for _, entity in pairs(e.entities) do
        ---@cast entity LuaEntity
        local recipe = entity.get_recipe()
        if not recipe and entity.type == "furnace" then
            recipe = entity.previous_recipe
        end
        if recipe then
            g.selection[recipe.name] = g.recipes[recipe.name]
        end
    end
    graph.refresh(player)
    gutils.fire_selection_change(g)
    player.cursor_stack.clear();
    if player.surface.index ~= g.surface.index then
        switch_surface(player)
    end
    gutils.recenter(g)
end

---@param e EventData.on_player_selected_area
local function on_player_selected_area(e)
    import_entities(e, true)
end

---@param e EventData.on_player_selected_area
local function on_player_alt_selected_area(e)
    import_entities(e, false)
end

tools.on_event(defines.events.on_player_selected_area, on_player_selected_area)

tools.on_event(defines.events.on_player_alt_selected_area,
    on_player_alt_selected_area)


---@param player LuaPlayer
---@param value boolean?
function main.set_speed(player, value)
    if not value then
        player.force.character_running_speed_modifier = 0
        player.force.manual_crafting_speed_modifier   = 0
    else
        player.force.character_running_speed_modifier = 3
        player.force.manual_crafting_speed_modifier   = 3
    end
end

gutils.exit = main.exit
gutils.enter = main.enter

return main
