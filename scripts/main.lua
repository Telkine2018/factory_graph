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

local excluded_subgroups = {
    ["empty-barrel"] = true,
    ["fill-barrel"] = true
}

---@param player LuaPlayer
---@param recipe_name string?
function main.enter(player, recipe_name)
    if string.find(player.surface.name, commons.surface_prefix_filter) then
        return
    end
    if player.gui.left[switch_button_name] then
        player.gui.left[switch_button_name].destroy()
    end

    local vars = tools.get_vars(player)
    vars.controller_type = player.controller_type
    vars.controller_position = player.position
    vars.controller_surface_index = player.surface_index

    local surface = main.enter_surface(player, recipe_name)
    if not vars.graph then
        local g = graph.new(surface)
        g.player = player
        vars.graph = g
        local recipes = player.force.recipes
        graph.update_recipes(g, recipes, excluded_categories, excluded_subgroups)
        graph.do_layout(g)
        graph.create_recipe_objects(g)
    end
    command.open(player)
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
                recipe = selected.previous_recipe
            end
        end
    end
    local recipe_name = recipe and recipe.name

    switch_surface(player, recipe_name)
end

script.on_event(prefix .. "-alt_k", on_switch_surface_by_key)

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
            local character = vars.saved_character
            if not player.character then
                if character then
                    if not character.valid and vars.saved_surface_index and vars.saved_position then
                        local characters = game.surfaces[vars.saved_surface_index].find_entities_filtered
                            { type = "character", position = vars.saved_position, radius = 2 }
                        if #characters == 0 then goto no_use end
                        character = characters[1]
                    end
                    vars.character = character
                    if vars.saved_force_index then
                        player.force = vars.saved_force_index
                    end
                end

                if string.find(player.surface.name, commons.surface_prefix_filter) then
                    main.exit(player)
                elseif character.surface_index == player.surface_index then
                    player.associate_character(character)
                    player.set_controller { type = defines.controllers.character, character = character }
                end
                ::no_use::
            end
        end
    end
end

tools.on_gui_click(prefix .. "_switch", on_switch_click)


local tile_name = commons.tile_name

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
    end

    for _, force in pairs(game.forces) do
        force.set_surface_hidden(surface, true)
    end

    local character        = player.character
    vars.surface           = surface
    vars.extern_surface    = player.surface
    vars.extern_position   = player.position
    vars.extern_force      = nil
    vars.extern_cheat_mode = player.cheat_mode
    local extern_force     = player.force
    if character then
        vars.character = character
        vars.saved_surface_index = vars.extern_surface.index
        vars.saved_position = vars.extern_position
        vars.saved_force_index = player.force_index
        player.disassociate_character(character)
    else
        vars.character = nil
        if vars.saved_force_index then
            player.force = vars.saved_force_index
        end
    end
    local controller_type
    controller_type = defines.controllers.ghost
    controller_type = defines.controllers.spectator
    controller_type = defines.controllers.god
    player.set_controller { type = controller_type }

    local g = gutils.get_graph(player)
    ---@type MapPosition
    local player_position = { 0, 0 }
    local grecipe
    if recipe_name then
        grecipe = g.recipes[recipe_name]
        if grecipe.visible then
            player_position = gutils.get_recipe_position(g, grecipe)
            g.player_position = nil
        else
            grecipe = nil
        end
    end

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
    vars.extern_force = extern_force
    if grecipe then
        drawing.draw_target(g, grecipe)
        local zoom = g.graph_zoom_level or 2
        player.zoom = zoom
    end
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

    if vars.extern_force then
        player.force = vars.extern_force
    end
    g.player_position = player.position

    local character = vars.character
    if character and character.valid then
        player.teleport(character.position, character.surface, false)
        player.associate_character(character)
        player.set_controller { type = defines.controllers.character, character = character }
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

        vars.extern_force = nil
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
        local vars = tools.get_vars(player)
        if not character or not character.valid then return end
        vars.saved_character = character
        vars.saved_force_index = player.force_index
        vars.saved_position = character.position
        vars.saved_surface_index = character.surface_index
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
                local recipes = player.force.recipes
                graph.update_recipes(g, recipes, g.excluded_categories, g.excluded_subgroups or {})

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
                end
                graph.deferred_update(player, { selection_changed = true, do_layout = need_refresh })
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
        if entity.type == "assembling-machine" or entity.type == "furnace" then
            local recipe = entity.get_recipe()
            if not recipe and entity.type == "furnace" then
                recipe = entity.previous_recipe.name
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
