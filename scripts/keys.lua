local luautil = require("__core__/lualib/util")


local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local drawing = require("scripts.drawing")

local prefix = commons.prefix

---@param player LuaPlayer
---@return Graph
---@return GRecipe?
local function prepare(player)
    local g = gutils.get_graph(player)
    local grecipe = g.selected_recipe
    if not grecipe then
        grecipe = g.move_recipe
        if not grecipe then
            return g
        end
    end

    g.move_recipe = grecipe
    drawing.clear_selection(g)
    return g, grecipe
end

---@param g Graph
---@param grecipe GRecipe
---@param col  integer
---@param line integer
local function move_recipe(g, grecipe, col, line)

    gutils.set_colline(g, grecipe, col, line)
    local x, y = gutils.get_position(g, col, line)
    grecipe.entity.teleport { x, y }
    drawing.redraw_selection(g.player)
end


--- @param e EventData.on_lua_shortcut
script.on_event(prefix .. "-up", function(e)
    local player = game.players[e.player_index]
    local g, grecipe = prepare(player)
    if not grecipe then return end

    local line = grecipe.line - 1
    local col = grecipe.col
    ---@cast col -nil
    local gcols = g.gcols
    local gcol = gcols[col]
    if gcol then
        while (gcol.line_set[line]) do
            line = line - 1
        end
    end
    move_recipe(g, grecipe, col, line)
end)

--- @param e EventData.on_lua_shortcut
script.on_event(prefix .. "-down", function(e)
    local player = game.players[e.player_index]
    local g, grecipe = prepare(player)
    if not grecipe then return end

    local line = grecipe.line + 1
    local col = grecipe.col
    ---@cast col -nil
    local gcols = g.gcols
    local gcol = gcols[col]
    if gcol then
        while (gcol.line_set[line]) do
            line = line + 1
        end
    end
    move_recipe(g, grecipe, col, line)
end)

--- @param e EventData.on_lua_shortcut
script.on_event(prefix .. "-left", function(e)
    local player = game.players[e.player_index]
    local g, grecipe = prepare(player)
    if not grecipe then return end

    local line = grecipe.line 
    local col = grecipe.col - 1
    ---@cast line -nil
    local gcols = g.gcols
    local gcol = gcols[col]
    if gcol then
        while gcols[col] and gcols[col].line_set[line] do
            col = col - 1
        end
    end
    move_recipe(g, grecipe, col, line)
end)

--- @param e EventData.on_lua_shortcut
script.on_event(prefix .. "-right", function(e)
    local player = game.players[e.player_index]
    local g, grecipe = prepare(player)
    if not grecipe then return end

    local line = grecipe.line 
    local col = grecipe.col + 1
    ---@cast line -nil
    local gcols = g.gcols
    local gcol = gcols[col]
    if gcol then
        while gcols[col] and gcols[col].line_set[line] do
            col = col + 1
        end
    end
    move_recipe(g, grecipe, col, line)
end)

--- @param e EventData.on_lua_shortcut
script.on_event(prefix .. "-del", function(e)
    local player = game.players[e.player_index]
    local g, grecipe = prepare(player)
    if not grecipe or not grecipe.entity or not grecipe.entity.valid then return end

    grecipe.visible = false
    g.selection[grecipe.name] = nil
    grecipe.entity.destroy()
    grecipe.entity = nil
    g.selected_recipe = nil
    g.selected_recipe_entity = nil
    drawing.redraw_selection(g.player)
    gutils.fire_selection_change(g)
end)
