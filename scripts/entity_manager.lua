local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local machinedb = require("scripts.machinedb")
local drawing = require("scripts.drawing")
local graph = require("scripts.graph")

local entity_manager = {}

---@param e  EventData.on_player_mined_entity
local function on_mined(e)
    local entity = e.entity

    if not entity or not entity.valid then return end

    local surface = entity.surface

    local surface_name = surface.name
    if not string.find(surface_name, commons.surface_prefix_filter) then
        return
    end

    local player_index = tonumber(string.sub(surface_name, 1 + #commons.surface_prefix))
    local player = game.players[player_index]

    local g = gutils.get_graph(player)
    if not g then return end

    
    local grecipe = g.entity_map[entity.unit_number]
    ---@cast grecipe GRecipe

    grecipe.visible = false
    g.selection[grecipe.name] = nil
    grecipe.entity = nil
    g.selected_recipe = nil
    g.selected_recipe_entity = nil
    drawing.redraw_selection(g.player)
    gutils.fire_selection_change(g)

    if e.buffer then
        e.buffer.clear()
    end
    gutils.set_cursor_stack(player, grecipe.name)
end

---@param ev EventData.on_player_mined_entity
local function on_player_mined_entity(ev)
    on_mined(ev)
end

local entity_filter = {
    { filter = 'name', name = commons.recipe_symbol_name },
    { filter = 'name', name = commons.product_symbol_name },
    { filter = 'name', name = commons.unresearched_symbol_name },
}

tools.on_event(defines.events.on_player_mined_entity, on_player_mined_entity, entity_filter)
tools.on_event(defines.events.on_robot_mined_entity, on_mined, entity_filter)
tools.on_event(defines.events.on_entity_died, on_mined, entity_filter)
tools.on_event(defines.events.script_raised_destroy, on_mined, entity_filter)


---@param entity LuaEntity
---@param e EventData.on_robot_built_entity | EventData.script_raised_built | EventData.script_raised_revive | EventData.on_built_entity
---@param  revive boolean?
local function on_build(entity, e, revive)
    if not entity or not entity.valid then return end

    local position = entity.position
    local surface = entity.surface
    entity.destroy()

    local surface_name = surface.name
    if not string.find(surface_name, commons.surface_prefix_filter) then
        return
    end

    local player_index = tonumber(string.sub(surface_name, 1 + #commons.surface_prefix))
    local player = game.players[player_index]

    local g = gutils.get_graph(player)
    if not g then return end

    if not e.stack then return end

    local recipe_name = e.stack.tags.recipe_name --[[@as string]]
    if not recipe_name then return end

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
    g.selection[recipe_name] = grecipe
    if grecipe.entity and grecipe.entity.valid then
        drawing.clear_selection(g)
        local x, y = gutils.get_position(g, grecipe.col, grecipe.line)
        grecipe.entity.teleport { x, y }
        drawing.redraw_selection(g.player)
    else
        grecipe.entity = nil
        drawing.clear_selection(g)
        graph.create_recipe_object(g, grecipe)
        drawing.redraw_selection(g.player)
    end
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


tools.on_event(defines.events.on_built_entity, on_player_built, entity_filter)
tools.on_event(defines.events.on_robot_built_entity, on_robot_built, entity_filter)
tools.on_event(defines.events.script_raised_built, on_script_built, entity_filter)
tools.on_event(defines.events.script_raised_revive, on_script_revive, entity_filter)


return entity_manager
