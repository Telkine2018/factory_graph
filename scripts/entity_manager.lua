local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local machinedb = require("scripts.machinedb")
local drawing = require("scripts.drawing")
local graph = require("scripts.graph")

local entity_manager = {}

local surface_prefix_filter = commons.surface_prefix_filter
local entity_names = { commons.recipe_symbol_name, commons.unresearched_symbol_name, commons.product_symbol_name }

local build_entity_filter = {
    { filter = 'name', name = commons.recipe_symbol_name },
    { filter = 'name', name = commons.product_symbol_name },
    { filter = 'name', name = commons.unresearched_symbol_name },
    { filter = 'name', name = "entity-ghost" },
}

local mine_entity_filter = {
    { filter = 'name', name = commons.recipe_symbol_name },
    { filter = 'name', name = commons.product_symbol_name },
    { filter = 'name', name = commons.unresearched_symbol_name },
}

---@param e  EventData.on_player_mined_entity
---@param to_cursor boolean?
local function do_mine(e, to_cursor)
    local entity = e.entity

    if not entity or not entity.valid then return end

    local surface = entity.surface
    local surface_name = surface.name
    if not string.find(surface_name, commons.surface_prefix_filter) then
        return
    end

    local player_index = tonumber(string.sub(surface_name, 1 + #commons.surface_prefix))
    local player = game.players[player_index]
    if not player then return end

    local g = gutils.get_graph(player)
    if not g then return end


    local grecipe = g.entity_map[entity.unit_number]
    ---@cast grecipe GRecipe

    if grecipe.visible then
        graph.remove_recipe_visibility(g, grecipe)
        grecipe.entity = nil
    end

    graph.deferred_redraw(player, true)

    if e.buffer then
        e.buffer.clear()
    end
    if to_cursor then
        gutils.set_cursor_stack(player, grecipe.name)
    end
end

---@param ev EventData.on_player_mined_entity
local function on_player_mined_entity(ev)
    do_mine(ev, true)
end

---@param e  EventData.on_player_mined_entity
local function on_mined(e)
    do_mine(e)
end

tools.on_event(defines.events.on_player_mined_entity, on_player_mined_entity, mine_entity_filter)
tools.on_event(defines.events.on_robot_mined_entity, on_mined, mine_entity_filter)
tools.on_event(defines.events.on_entity_died, on_mined, mine_entity_filter)
tools.on_event(defines.events.script_raised_destroy, on_mined, mine_entity_filter)


---@param entity LuaEntity
---@param e EventData.on_robot_built_entity | EventData.script_raised_built | EventData.script_raised_revive | EventData.on_built_entity
---@param  revive boolean?
local function on_build(entity, e, revive)
    if not entity or not entity.valid then return end

    local position = entity.position
    local surface = entity.surface

    local surface_name = surface.name
    if not string.find(surface_name, commons.surface_prefix_filter) then
        entity.destroy()
        return
    end

    local player_index = tonumber(string.sub(surface_name, 1 + #commons.surface_prefix))
    local player = game.players[player_index]
    local g = gutils.get_graph(player)
    if not g then return end

    local recipe_name
    local tags
    local selected = true
    if entity.name == "entity-ghost" then
        tags = entity.tags
        if tags then
            recipe_name = entity.tags.recipe_name --[[@as string]]
            selected = tags.selected --[[@as boolean]]
        end
    elseif e.stack then
        tags = e.stack.tags
        if tags then
            recipe_name = tags.recipe_name --[[@as string]]
            selected = tags.selected --[[@as boolean]]
        end
    end

    entity.destroy()
    if not recipe_name then
        return
    end

    local grecipe = g.recipes[recipe_name]
    if not grecipe then return end

    local col, line = gutils.get_colline(g, position.x, position.y)
    if grecipe.col then
        local gcol = g.gcols[grecipe.col]
        gcol.line_set[grecipe.line] = nil
        grecipe.col = nil
        grecipe.line = nil
    end
    graph.insert_recipe_at_position(g, grecipe, col, line)
    grecipe.visible = true
    if selected ~= false then
        g.selection[recipe_name] = grecipe
    end
    if grecipe.entity and grecipe.entity.valid then
        drawing.clear_selection(g)
        local x, y = gutils.get_position(g, grecipe.col, grecipe.line)
        grecipe.entity.teleport { x, y }
    else
        grecipe.entity = nil

        drawing.clear_selection(g)
        graph.create_recipe_object(g, grecipe)
    end
    graph.deferred_redraw(player, true)
end

---@param ev EventData.on_robot_built_entity
local function on_robot_built(ev)
    local entity = ev.created_entity

    on_build(entity, ev)
end

---@param ev EventData.script_raised_built
local function on_script_built(ev)
    local entity = ev.entity

    on_build(entity, ev)
end

---@param ev EventData.script_raised_revive
local function on_script_revive(ev)
    local entity = ev.entity

    on_build(entity, ev, true)
end

---@param e EventData.on_built_entity
local function on_player_built(e)
    local entity = e.created_entity

    on_build(entity, e)
end


tools.on_event(defines.events.on_built_entity, on_player_built, build_entity_filter)
tools.on_event(defines.events.on_robot_built_entity, on_robot_built, build_entity_filter)
tools.on_event(defines.events.script_raised_built, on_script_built, build_entity_filter)
tools.on_event(defines.events.script_raised_revive, on_script_revive, build_entity_filter)

tools.on_event(defines.events.on_marked_for_deconstruction,
    ---@param e EventData.on_marked_for_deconstruction
    function(e)
        if not e.entity.valid then return end
        if not string.find(e.entity.surface.name, surface_prefix_filter) then return end

        e.entity.destroy { raise_destroy = true }
    end, {
        { filter = "name", name = commons.recipe_symbol_name,       mode = "or" },
        { filter = "name", name = commons.unresearched_symbol_name, mode = "or" },
        { filter = "name", name = commons.product_symbol_name,      mode = "or" }
    }
)

---@param bp LuaItemStack
---@param mapping table<integer, LuaEntity>
---@param g Graph
local function register_mapping(bp, mapping, g)
    local bp_count = bp.get_blueprint_entity_count()
    if #mapping ~= 0 then
        for index = 1, bp_count do
            local entity = mapping[index]
            if entity and entity.valid then
                local grecipe = g.entity_map[entity.unit_number]
                if grecipe then
                    local selected = g.selection[grecipe.name] ~= nil
                    bp.set_blueprint_entity_tags(index, { recipe_name = grecipe.name, selected = selected })
                end
            end
        end
    elseif bp_count > 0 then
        local bp_entities = bp.get_blueprint_entities()
        if bp_entities then
            for index = 1, bp_count do
                local entity = bp_entities[index]
                if string.find(entity.name, "") then
                    local entities = surface.find_entities_filtered {
                        name = entity_names,
                        position = entity.position,
                        radius = 0.1
                    }
                    if #entities == 1 then
                        local entity = entities[1]
                        local grecipe = g.entity_map[entity.unit_number]
                        if grecipe then
                            local selected = g.selection[grecipe.name] ~= nil
                            bp.set_blueprint_entity_tags(index, { recipe_name = grecipe.name, selected = selected })
                        end
                    end
                end
            end
        end
    end
end

local function on_register_bp(e)
    local player = game.get_player(e.player_index)
    ---@cast player -nil
    local vars = tools.get_vars(player)
    if e.gui_type == defines.gui_type.item and e.item and e.item.is_blueprint and
        e.item.is_blueprint_setup() and player.cursor_stack and
        player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint and
        not player.cursor_stack.is_blueprint_setup() then
        vars.previous_bp = { blueprint = e.item, tick = e.tick }
    else
        vars.previous_bp = nil
    end
end

---@param player LuaPlayer
---@return LuaItemStack?
local function get_bp_to_setup(player)
    -- normal drag-select
    local bp = player.blueprint_to_setup
    if bp and bp.valid_for_read and bp.is_blueprint_setup() then return bp end

    -- alt drag-select (skips configuration dialog)
    bp = player.cursor_stack
    if bp and bp.valid_for_read and bp.is_blueprint and bp.is_blueprint_setup() then
        while bp.is_blueprint_book do
            bp = bp.get_inventory(defines.inventory.item_main)[bp.active_index]
        end
        return bp
    end

    -- update of existing blueprint
    local previous_bp = tools.get_vars(player).previous_bp
    if previous_bp and previous_bp.tick == game.tick and previous_bp.blueprint and
        previous_bp.blueprint.valid_for_read and
        previous_bp.blueprint.is_blueprint_setup() then
        return previous_bp.blueprint
    end
end

tools.on_event(defines.events.on_player_setup_blueprint,
    ---@param e EventData.on_player_setup_blueprint
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        if not g then return end
        if not string.find(player.surface.name, commons.surface_prefix_filter) then return end
        ---@type table<integer, LuaEntity>
        local mapping = e.mapping.get()
        local bp = get_bp_to_setup(player)
        if bp then register_mapping(bp, mapping, g) end
    end)

tools.on_event(defines.events.on_gui_closed, on_register_bp)

return entity_manager
