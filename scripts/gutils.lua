local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")

local gutils = {}

---@param ids integer[]?
---@return nil
function gutils.destroy_drawing(ids)
    if not ids then return nil end

    for _, id in pairs(ids) do
        rendering.destroy(id)
    end
    return nil
end

--#region colors

local color_func = {
    [0] = function(c, x, m) return { c, x, 0 } end,
    [1] = function(c, x, m) return { x, c, 0 } end,
    [2] = function(c, x, m) return { 0, c, x } end,
    [3] = function(c, x, m) return { 0, x, c } end,
    [4] = function(c, x, m) return { x, c, 0 } end,
    [5] = function(c, x, m) return { c, 0, x } end
}

---@param h number      -- 0..360
---@param s number      -- 0..1
---@param l number      -- 0..1
---@return Color
function gutils.create_color(h, s, l)
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs(h / 60 % 2 - 1))
    local m = l - c / 2

    if (h >= 360) then
        h = 0
    end
    local color = color_func[math.floor(h / 60)](c, x, m)
    return color
end

---@param h number      -- 0..360
---@return Color
function gutils.create_hcolor(h)
    return gutils.create_color(h, 1, 0.5)
end

---@return Color
function gutils.create_random_color()
    local h = math.random(0, 72) * 5
    return gutils.create_hcolor(h)
end

---@param g Graph
---@param product GProduct
function gutils.get_product_color(g, product)
    if product.color then return product.color end

    product.color = gutils.create_hcolor(g.color_index)
    local color_index = g.color_index
    color_index = color_index + 95
    if color_index >= 360 then
        color_index = color_index - 360
    end
    g.color_index = color_index
    return product.color
end

gutils.colors = {
    { 0,         1,         0 },
    { 1,         0,         0 },
    { 0,         1,         1 },
    { 1,         106 / 255, 0 },
    { 1,         216 / 255, 0 },
    { 182 / 255, 1,         0 },
    { 0,         0,         1 },
}

--#endregion

---@param recipe GRecipe
---@return {[string]:GProduct}
function gutils.product_set(recipe)
    local result = {}
    for _, product in pairs(recipe.ingredients) do
        result[product.name] = product
    end
    for _, product in pairs(recipe.products) do
        result[product.name] = product
    end
    return result
end

---@param player LuaPlayer
---@return Graph
function gutils.get_graph(player)
    return tools.get_vars(player).graph
end

local match = string.match

---@param player LuaPlayer
---@param grecipe GRecipe
---@return LocalisedString
function gutils.get_recipe_name(player, grecipe)
    ---@type LocalisedString
    local localised_name

    if grecipe.is_product then
        if match(grecipe.name, "^item/") then
            localised_name = translations.get_item_name(player.index, string.sub(grecipe.name, 6))
        else -- fluid
            localised_name = translations.get_fluid_name(player.index, string.sub(grecipe.name, 7))
        end
    else
        localised_name = translations.get_recipe_name(player.index, grecipe.name)
    end
    return localised_name
end

---@param player LuaPlayer
---@param name string
---@return LocalisedString
function gutils.get_product_name(player, name)
    if match(name, "^item/") then
        localised_name = translations.get_item_name(player.index, string.sub(name, 6))
    else -- fluid
        localised_name = translations.get_fluid_name(player.index, string.sub(name, 7))
    end
    return localised_name
end

---@param g Graph
---@param recipe GRecipe
function gutils.get_position(g, recipe)
    local grid_size = g.grid_size
    local x = recipe.col * grid_size + 0.5
    local y = recipe.line * grid_size + 0.5
    return { x = x, y = y }
end

---@param player LuaPlayer
---@param position MapPosition
function gutils.move_view(player, position)
    local speed = 50 / 60.0
    local origin = player.position
    local dx = (position.x - origin.x)
    local dy = (position.y - origin.y)
    local dist = math.sqrt(dx * dx + dy * dy)
    local count = math.ceil(dist / speed)
    if count == 0 then return end
    dx = dx / count
    dy = dy / count
    if not global.recipe_move then
        global.recipe_move = {}
    end
    global.recipe_move[player.index] = {
        x = origin.x,
        y = origin.y,
        dx = dx,
        dy = dy,
        count = count
    }
end

---@class MoveProcess
---@field dx number
---@field dy number
---@field count integer

local function move_tick_handler()
    ---@type {[integer]:MoveProcess}
    local moves = global.recipe_move
    if not moves then return end

    local toremove = {}
    for player_index, move in pairs(moves) do
        local count = move.count
        local player = game.players[player_index]
        count = count - 1
        if count <= 0 then
            toremove[player_index] = true
        else
            local pos = player.position
            local x = pos.x + move.dx
            local y = pos.y + move.dy
            player.teleport({ x, y }, player.surface, false)
            move.count = count
        end
    end
    for player_index, _ in pairs(toremove) do
        moves[player_index] = nil
    end
    if table_size(moves) == 0 then
        global.recipe_move = nil
    end
end
tools.on_event(defines.events.on_tick, move_tick_handler)

---@param g Graph
---@param recipe GRecipe?
---@return boolean
function gutils.select_current_recipe(g, recipe)
    if not recipe then return false end
    if g.selection[recipe.name] then return false end
    g.selection[recipe.name] = recipe
    return true
end

---@param g Graph
function gutils.set_visibility_to_selection(g)
    local selection = g.selection
    if not selection then
        selection = {}
    end
    for _, grecipe in pairs(g.recipes) do
        grecipe.line = nil
        grecipe.col = nil
        grecipe.selector_positions = nil
        if selection[grecipe.name] then
            grecipe.visible = true
        else
            grecipe.visible = false
        end
    end
end

---@param g Graph
function gutils.set_full_visibility(g)
    for _, grecipe in pairs(g.recipes) do
        grecipe.line = nil
        grecipe.col = nil
        grecipe.selector_positions = nil
        grecipe.visible = true
    end
end

return gutils
