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
function gutils.compute_visibility(g)
    local show_only_researched = g.show_only_researched
    if g.visibility == commons.visibility_selection then
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
                if show_only_researched and not grecipe.enabled then
                    grecipe.visible = false
                end
            else
                grecipe.visible = false
            end
        end
    else -- if g.visibility == commons.visibility_all then
        for _, grecipe in pairs(g.recipes) do
            grecipe.line = nil
            grecipe.col = nil
            grecipe.selector_positions = nil
            grecipe.visible = true
            if show_only_researched and not grecipe.enabled then
                grecipe.visible = false
            end
        end
    end
end

---@param g Graph
---@return table<string, GProduct>
function gutils.get_visible_products(g)
    local products = {}
    for _, product in pairs(g.products) do
        for _, grecipe in pairs(product.ingredient_of) do
            if grecipe.visible then
                products[product.name] = product
                goto skip
            end
        end
        for _, grecipe in pairs(product.product_of) do
            if grecipe.visible then
                products[product.name] = product
                goto skip
            end
        end
        ::skip::
    end
    return products
end

---@generic KEY
---@param recipes table<KEY, GRecipe>
---@return table<KEY, GRecipe>
function gutils.filter_enabled_recipe(recipes)
    local new_recipes = {}
    for key, recipe in pairs(recipes) do
        if recipe.enabled then
            new_recipes[key] = recipe
        end
    end
    return new_recipes
end

---@param grecipe GRecipe
function gutils.get_connected_recipe(grecipe)
    local result = gutils.get_connected_ingredients(grecipe)
    gutils.get_connected_productions(grecipe)
    result[grecipe.name] = nil
    return result
end

---@param grecipe GRecipe
---@param result table<string, GRecipe>?
---@return table<string, GRecipe>
function gutils.get_connected_ingredients(grecipe, result)

    if not result then result = {} end

    for _, ingredient in pairs(grecipe.ingredients) do
        for _, irecipe in pairs(ingredient.product_of) do
            if irecipe.visible then
                result[irecipe.name] = irecipe
            end
        end
    end
    return result
end

---@param grecipe GRecipe
---@param result table<string, GRecipe>?
---@return table<string, GRecipe>
function gutils.get_connected_productions(grecipe, result)

    if not result then result = {} end

    for _, product in pairs(grecipe.products) do
        for _, precipe in pairs(product.ingredient_of) do
            if precipe.visible then
                result[precipe.name] = precipe
            end
        end
    end
    return result
end

---@param g Graph
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return table<string, GProduct>
function gutils.get_product_flow(g)

    ---@type table<string, GProduct>
    local inputs
    ---@type table<string, GProduct>
    local outputs
    ---@type table<string, GProduct>
    local intermediates

    inputs = {}
    outputs = {}
    intermediates = {}
    for _, recipe in pairs(g.recipes) do
        if recipe.visible then
            for _, ingredient in pairs(recipe.ingredients) do
                local name = ingredient.name
                inputs[name] = ingredient
            end
        end
    end
    for _, recipe in pairs(g.recipes) do
        if recipe.visible then
            for _, product in pairs(recipe.products) do
                local name = product.name
                if inputs[name] then
                    intermediates[name] = product
                    inputs[name] = nil
                else
                    outputs[name] = product
                end
            end
        end
    end
    return inputs, outputs, intermediates
end


local line_margin = 5

---@param flow LuaGuiElement
---@param title LocalisedString?
function gutils.add_line(flow, title)
    if not title then
        line = flow.add { type = "line" }
        line.style.top_margin = line_margin
        line.style.bottom_margin = line_margin
    else
        local hflow = flow.add { type = "flow", direction = "horizontal" }
        hflow.add { type = "label", caption = title }
        local line = hflow.add { type = "line" }
        line.style.top_margin = 10
        hflow.style.top_margin = 3
        hflow.style.bottom_margin = 5
    end
end



return gutils
