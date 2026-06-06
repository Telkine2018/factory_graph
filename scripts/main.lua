local mod_gui = require("mod-gui")
local dictionary = require("__flib__/dictionary")
local migration = require("__flib__/migration")

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
local recipe_selection = require("scripts.recipe_selection")

local main = {}

local surface_prefix = commons.surface_prefix
local recipe_symbol_name = prefix .. "-recipe-symbol"

local switch_button_name = prefix .. "-switch"

local function np(name)
    return prefix .. "-main." .. name
end

---@param msg string
local function _log(msg)
    -- log(msg)
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
    ["transport-fluid-request"] = true
}

if not settings.startup["factory_graph-include-recycling-recipes"] then
    excluded_categories["recycling"] = true
    excluded_categories["recycling-or-hand-crafting"] = true
end

local barreling_subgroups = {
    ["empty-barrel"] = true,
    ["fill-barrel"] = true
}

if settings.startup["factory_graph-include-barreling-recipes"] then
    excluded_categories.barrelling = nil
    excluded_categories["barreling-pump"] = nil
    barreling_subgroups = {}
end

---@param g Graph
function main.reload_recipe(g)

    local recipes = g.player.force.recipes
    graph.update_recipes(g, recipes, excluded_categories, barreling_subgroups)

end

---@param player LuaPlayer
---@param recipe_name string?
function main.enter(player, recipe_name)
    if string.find(player.surface.name, commons.surface_prefix_filter) then
        return
    end
    if player.gui.left[switch_button_name] then
        player.gui.left[switch_button_name].destroy()
    end

    _log("main.enter")

    main.enter_surface(player, recipe_name)
end

---@param player LuaPlayer
---@param recipe_name string?
local function switch_surface(player, recipe_name)
    if not string.find(player.surface.name, commons.surface_prefix_filter) then
        main.enter(player, recipe_name)
    else
        main.exit(player)
    end
end

---@param e EventData.on_lua_shortcut
local function on_switch_surface_by_key(e)
    local player = game.players[e.player_index]
    local selected = player.selected
    local recipe
    if selected then
        local type = selected.type
        if type == "assembling-machine" or type == "furnace" then
            recipe = selected.get_recipe()
            if not recipe and type == "furnace" then
                recipe = selected.previous_recipe and selected.previous_recipe.name
            end
        end
    end
    local recipe_name = recipe and recipe.name

    switch_surface(player, recipe_name)
end

script.on_event(prefix .. "-alt_k", on_switch_surface_by_key)

---@param e EventData.on_gui_click
function on_switch_click(e)
    local player = game.players[e.player_index]
    if e.button == defines.mouse_button_type.left then
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
            ---@type Extern
            local extern = vars.extern
            extern.show_surface_list = true
            main.exit(player)
        end
    elseif e.button == defines.mouse_button_type.right then
        if not (e.control or e.shift or e.alt) then
            local g = gutils.get_graph(player)
            if not g then return end
            recipe_selection.open(g, {})
        end
    end
end

tools.on_gui_click(prefix .. "_switch", on_switch_click)


local tile_name = commons.tile_name

---@param player LuaPlayer
---@param show_surface_list boolean?
local function save_state(player, show_surface_list)
    local vars = tools.get_vars(player)
    local surface = player.surface

    if string.find(surface.name, commons.surface_prefix_filter) then
        ---@type Graph?
        local g = vars.graph
        if g and vars.extern and vars.extern.in_graph then
            g.player_position = player.position
            if g.graph_zoom_level_cmd then
                player.zoom = g.graph_zoom_level_cmd
                g.graph_zoom_level_cmd = nil
            elseif g.graph_zoom_level ~= player.zoom then
                g.graph_zoom_level = player.zoom
                _log("Save zoom:" .. g.graph_zoom_level)
            end
            if show_surface_list and player.game_view_settings.show_surface_list then
                player.game_view_settings.show_surface_list = false
            end
        end
        return false
    else
        local extern = vars.extern
        if not extern then
            extern = {}
            vars.extern = extern
        end
        if extern.in_graph then
            return
        end
        extern.surface           = surface
        extern.position          = player.position
        extern.force             = player.force
        extern.cheat_mode        = player.cheat_mode
        extern.controller        = player.controller_type
        extern.show_surface_list = player.game_view_settings.show_surface_list
        extern.character         = player.character
        extern.zoom              = player.zoom
        return true
    end
end

---@param player LuaPlayer
---@param recipe_name string?
---@return LuaSurface
function main.enter_surface(player, recipe_name)
    local vars = tools.get_vars(player)

    if not prototypes.tile[tile_name] then
        tile_name = "lab-dark-2"
    end

    local surface_name = surface_prefix .. player.index
    local surface = game.surfaces[surface_name]

    if not surface then
        local starting_points = nil
        if script.active_mods["rso-mod"] then
            starting_points = { { x = 0, y = 0 } }
        end

        local settings = {
            height = 1000,
            width = 1000,
            autoplace_controls = {},
            default_enable_all_autoplace_controls = false,
            cliff_settings = { cliff_elevation_0 = 1024 },
            starting_area = "none",
            starting_points = starting_points,
            terrain_segmentation = "none",
            autoplace_settings = {
                entity = { treat_missing_as_default = false, frequency = "none" },
                tile = {
                    treat_missing_as_default = false,
                    settings = {
                        [tile_name] = {}
                    }
                },
                decorative = { treat_missing_as_default = false, frequency = "none" }
            },
            property_expression_names = {
                cliffiness = 0,
                ["tile:water:probability"] = -10000,
                ["tile:deep-water:probability"] = -10000,
                ["tile:" .. tile_name .. ":probability"] = "inf"
            }
        }

        surface = game.create_surface(surface_name, settings)
        surface.map_gen_settings = settings
        surface.daytime = 0
        surface.freeze_daytime = true
        surface.show_clouds = false
        surface.generate_with_lab_tiles = commons.generate_with_lab_tiles

        surface.create_entity { name = commons.radar_name, position = { 0, 0 }, force = player.force }
    end

    for _, force in pairs(game.forces) do
        force.set_surface_hidden(surface, true)
    end

    save_state(player, false)

    local g = gutils.get_graph(player)

    ---@type MapPosition
    local player_position = { 0, 0 }
    if g then
        player_position = g.player_position
    end

    if g then
        g.highlight_recipe = recipe_name
        if recipe_name then
            ---@type GRecipe?
            local grecipe = g.recipes[recipe_name]
            if not grecipe or not grecipe.visible then
                grecipe = nil
                for _, crecipe in pairs(g.selection) do
                    if crecipe.derived_from and crecipe.derived_from.name == recipe_name and crecipe.visible then
                        grecipe = crecipe
                        break
                    end
                end
            end
            if grecipe then
                player_position = gutils.get_recipe_position(g, grecipe)
                g.player_position = player_position
                g.highlight_recipe = grecipe.name
            end
        end
    end

    local controller_type = defines.controllers.remote
    player.set_controller { type = controller_type, surface = surface, position = player_position }
    return surface
end

tools.on_nth_tick(30, function(data)
    local index = 0
    for _, player in pairs(game.players) do
        save_state(player, true)
        index = index + 1
        if index > 10 then return end
    end
end)

---@param player LuaPlayer
function main.exit(player)
    local vars = tools.get_vars(player)
    ---@type Graph?
    local g = vars.graph
    if not g then return end

    ---@type Extern
    local extern = vars.extern
    if extern then
        extern.in_graph = nil
    end

    _log("main.exit")

    if g.surface.index ~= player.surface_index then 
        player.game_view_settings.show_surface_list = true
        return 
    end

    if extern then
        if extern.controller == defines.controllers.god then
            player.set_controller { type = defines.controllers.remote, position = extern.position, surface = extern.surface }
            return
        end
    end
    player.exit_remote_view()
end

tools.on_event(defines.events.on_player_changed_surface,
    ---@param e EventData.on_player_changed_surface
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local from_surface = game.surfaces[e.surface_index]
        local to_surface = player.surface

        _log("on_player_changed_surface: from=" .. from_surface.name .. ",to=" .. to_surface.name)

        -- from surface
        if string.find(from_surface.name, commons.surface_prefix_filter) then
            tools.close_panels(player)
            command.close(player)

            ---@type Extern
            local extern = vars.extern
            if not extern then return end

            local saved_zoom = extern.zoom
            local saved_surface = extern.surface
            local saved_position = extern.position
            local saved_controller = extern.controller
            local save_show_surface_list = true
            local save_show_minimap = true

            player.force = extern.force
            player.cheat_mode = extern.cheat_mode
            extern.in_graph = nil

            if (saved_controller == defines.controllers.remote)
            then
                if player.controller_type ~= defines.controllers.remote or
                    player.surface.index ~= saved_surface.index or
                    tools.distance(saved_position, player.position) > 3 then
                    player.set_controller { type = saved_controller, position = saved_position, surface = saved_surface }
                end
                if saved_zoom then
                    player.zoom = saved_zoom
                end
            else
                if (saved_controller == defines.controllers.god and player.controller_type == defines.controllers.character)
                then
                    player.set_controller { type = defines.controllers.remote, position = saved_position, surface = saved_surface }
                end
            end

            local settings = player.game_view_settings
            settings.show_surface_list = save_show_surface_list
            settings.show_minimap = save_show_minimap
            settings.show_entity_tooltip = true
            settings.show_tool_bar = true
            settings.show_quickbar = true
            return
        end

        if string.find(to_surface.name, commons.surface_prefix_filter) then
            if vars.extern then
                vars.extern.in_graph = true
            end

            ---@type Graph?
            local g = vars.graph
            if not g then
                g = graph.new(to_surface)
                g.player = player
                vars.graph = g
                main.reload_recipe(g)
                if g.visibility == commons.visibility_selection then
                    for _, grecipe in pairs(g.recipes) do
                        grecipe.visible = nil
                    end
                end
                graph.do_layout(g)
                graph.create_recipe_objects(g)
            else
                if player.controller_type ~= defines.controllers.remote then
                    player.set_controller { type = defines.controllers.remote, position = g.player_position }
                end
            end

            if g.highlight_recipe then
                local grecipe = g.recipes[g.highlight_recipe]
                if grecipe and grecipe.visible then
                    drawing.draw_target(g, grecipe)
                end
                g.highlight_recipe = nil
            end

            command.open(player)
            player.force = "player"
            player.cheat_mode = false
            local settings = player.game_view_settings
            settings.show_surface_list = false
            settings.show_minimap = false
            settings.show_entity_tooltip = false
            settings.show_tool_bar = false
            settings.show_quickbar = false

            player.zoom = g.graph_zoom_level
            g.graph_zoom_level_cmd = g.graph_zoom_level
            _log("Enter zoom:" .. player.zoom)
        end
    end)

---@param player LuaPlayer
function main.legacy_exit(player)
    local vars = tools.get_vars(player)
    local g = vars.graph

    if not g then return end
    if g.surface.index ~= player.surface_index then return end

    local extern_position = vars.extern_position
    if not extern_position and vars.character then
        extern_position = vars.character.position
    end

    if vars.extern_force then
        player.force = vars.extern_force
    end
    g.player_position = player.position

    local character = vars.character
    if character and character.valid then
        local surface = character.surface
        player.teleport(character.position, surface, false)
        player.associate_character(character)
        player.set_controller { type = defines.controllers.character, character = character }
        if surface then
            local platform = surface.platform
            if platform then
                player.enter_space_platform(platform)
            end
        end
        if vars.extern_cheat_mode then
            if vars.extern_cheat_mode ~= character.cheat_mode then
                character.cheat_mode = vars.extern_cheat_mode
            end
        else
            character.cheat_mode = false
        end
        vars.character = nil
        if vars.controller_type == defines.controllers.remote then
            player.set_controller {
                type = defines.controllers.remote,
                position = vars.controller_position,
                surface = vars.controller_surface_index }
        end
    elseif vars.extern_position and vars.extern_surface and vars.extern_surface.valid then
        player.teleport(vars.extern_position, vars.extern_surface, false)
    elseif player.physical_surface and player.physical_surface.valid then
        player.teleport(player.physical_position, player.physical_surface, false)
    elseif vars.extern_position then
        player.teleport(vars.extern_position, "Nauvis", false)
    elseif vars.extern_position then
        player.teleport({ 0, 0 }, "Nauvis", false)
    end
end

tools.on_event(defines.events.on_player_changed_position,
    ---@param e EventData.on_player_changed_position
    function(e)
        local player = game.players[e.player_index]
        local character = player.character
        local vars = tools.get_vars(player)

        ---@type Graph
        local g = vars.graph
        if not g then return end

        if player.surface.index ~= g.surface.index then
            if not character or not character.valid then return end
            save_state(player)
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
    local to_delete = {}
    for _, surface in pairs(game.surfaces) do
        if string.find(surface.name, commons.surface_prefix_filter) then
            table.insert(to_delete, surface.name)
        end
    end
    for _, name in pairs(to_delete) do
        game.delete_surface(name)
    end

    picker_dolly_install()
end)

tools.on_event(defines.events.on_player_created,
    ---@param e EventData.on_player_created
    function(e)
        local player = game.players[e.player_index]
        create_player_button(player)
    end)

tools.on_configuration_changed(
---@param data ConfigurationChangedData
    function(data)
        picker_dolly_install()
        for _, player in pairs(game.players) do
            create_player_button(player)

            local vars = tools.get_vars(player)

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
                main.reload_recipe(g)

                local need_refresh
                for _, grecipe in pairs(g.recipes) do
                    if grecipe.visible and (not grecipe.line and not grecipe.col) then
                        need_refresh = true
                    end
                    grecipe.layer = tools.check_sprite(grecipe.layer)
                end
                g.current_layer = tools.check_sprite(g.current_layer)
                if g.visible_layers then
                    for layer in pairs(g.visible_layers) do
                        if not tools.check_sprite(layer) then
                            g.visible_layers = {}
                            g.visibility = commons.visibility_selection
                            need_refresh = true
                            break
                        end
                    end
                end
                if data.mod_changes
                    and data.mod_changes.factory_graph
                    and data.mod_changes.factory_graph.old_version then
                    if migration.is_newer_version(data.mod_changes.factory_graph.old_version, "1.0.3") then
                        g.surface.generate_with_lab_tiles = commons.generate_with_lab_tiles
                        g.surface.clear()
                    end

                    if migration.is_newer_version(data.mod_changes.factory_graph.old_version, "1.0.7") then
                        g.line_gap = 0.2
                        g.always_use_full_selection = false
                    end

                    if migration.is_newer_version(data.mod_changes.factory_graph.old_version, "2.0.0") then
                        g.graph_ids = tools.render_translate_table(g.graph_ids)
                        g.graph_select_ids = tools.render_translate_table(g.graph_select_ids)
                        g.highlighted_recipes_ids = tools.render_translate_table(g.highlighted_recipes_ids)
                        g.selector_id = tools.render_translate(g.selector_id)
                        g.selector_product_name_id = tools.render_translate(g.selector_product_name_id)
                        g.layer_ids = tools.render_translate_table(g.layer_ids)
                        for _, gproduct in pairs(g.products) do
                            gproduct.ids = tools.render_translate_table(g.ids)
                        end
                    end
                    if migration.is_newer_version(data.mod_changes.factory_graph.old_version, "2.0.24") then
                        for _, player in pairs(game.players) do
                            local g = gutils.get_graph(player)
                            if g then
                                if player.surface_index == g.surface.index then
                                    main.legacy_exit(player)
                                end
                                g.surface.create_entity { name = commons.radar_name, position = { 0, 0 }, force = player.force }
                            end
                        end
                    end
                end
                graph.deferred_update(player, { selection_changed = true, do_layout = need_refresh })

                -- Cleaning
                local vars = tools.get_vars(player)
                vars.extern_surface = nil
                vars.extern_position = nil
                vars.extern_cheat_mode = nil
                vars.extern_force = nil

                vars.saved_surface_index = nil
                vars.saved_force_index = nil
                vars.saved_position = nil
                vars.saved_character = nil

                vars.controller_type = nil
                vars.controller_position = nil
                vars.controller_surface_index = nil
            end
        end
    end)

tools.on_event(defines.events.on_surface_cleared,
    ---@param e EventData.on_surface_cleared
    function(e)
        local surface = game.surfaces[e.surface_index]
        if not string.find(surface.name, commons.surface_prefix_filter) then
            return
        end
        local player_index = tonumber(string.sub(surface.name, #commons.surface_prefix + 1))
        local player = game.players[player_index]
        graph.deferred_update(player, { selection_changed = true, do_redraw = true })
    end
)

local tile_name = commons.tile_name

tools.on_event(defines.events.on_chunk_generated,
    ---@param e EventData.on_chunk_generated
    function(e)
        local surface = e.surface
        if not string.find(surface.name, commons.surface_prefix_filter) then
            return
        end
        local tiles = {}
        local xstart = e.position.x * 32
        local ystart = e.position.y * 32
        for y = 0, 31 do
            for x = 0, 31 do
                table.insert(tiles, { position = { xstart + x, ystart + y }, name = tile_name })
            end
        end
        surface.set_tiles(tiles, false)
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
            if player.valid and player.force_index == force_index then
                local g = gutils.get_graph(player)
                if g then
                    g.recipes_productivities = nil
                    local need_refresh
                    for _, effect in pairs(tech.prototype.effects) do
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
                    g.recipes_productivities = nil
                    for _, effect in pairs(tech.prototype.effects) do
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
        if entity.type == "assembling-machine" or entity.type == "furnace" then
            local recipe = entity.get_recipe()
            if not recipe and entity.type == "furnace" then
                recipe = entity.previous_recipe and entity.previous_recipe.name
            end
            if recipe then
                g.selection[recipe.name] = g.recipes[recipe.name]
            end
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
---@param value integer?
function main.set_speed(player, value)
    if not value then
        value = 0
    end
    player.force.character_running_speed_modifier = value
    player.force.manual_crafting_speed_modifier   = value
end

gutils.exit = main.exit
gutils.enter = main.enter

return main
