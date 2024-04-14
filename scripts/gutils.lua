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
---@param line integer
---@param col integer
---@return number
---@return number
function gutils.get_position(g, col, line)
    local grid_size = g.grid_size
    local x = col * grid_size + 0.5
    local y = line * grid_size + 0.5
    return x, y
end

---@param g Graph
---@param x number
---@param y number
---@return number
---@return number
function gutils.get_colline(g, x, y)
    local grid_size = g.grid_size
    local col = math.floor((x - 0.5 + grid_size / 2) / grid_size)
    local line = math.floor((y - 0.5 + grid_size / 2) / grid_size)
    return col, line
end

---@param g Graph
---@param recipe GRecipe
function gutils.get_recipe_position(g, recipe)
    local x, y = gutils.get_position(g, recipe.col, recipe.line)
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

---@param player LuaPlayer
---@param recipe_name string
---@param fast boolean?
function gutils.move_to_recipe(player, recipe_name, fast)
    local g = gutils.get_graph(player)
    if not g then return end

    if g.surface ~= player.surface then return end

    local grecipe = g.recipes[recipe_name]
    if not grecipe or not grecipe.line then return end

    local position = gutils.get_recipe_position(g, grecipe)

    if fast then
        player.teleport(position)
    else
        gutils.move_view(player, position)
    end
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
---@param keep_position boolean?
function gutils.compute_visibility(g, keep_position)
    local show_only_researched = g.show_only_researched
    if g.visibility == commons.visibility_selection then
        local selection = g.selection
        if not selection then
            selection = {}
        end
        for _, grecipe in pairs(g.recipes) do
            grecipe.selector_positions = nil
            grecipe.entity = nil
            if selection[grecipe.name] then
                if not keep_position then
                    grecipe.line = nil
                    grecipe.col = nil
                end
                grecipe.visible = true
                if show_only_researched and not grecipe.enabled then
                    grecipe.visible = false
                end
            else
                grecipe.line = nil
                grecipe.col = nil
                grecipe.visible = false
            end
        end
    else -- if g.visibility == commons.visibility_all then
        for _, grecipe in pairs(g.recipes) do
            if not keep_position then
                grecipe.line = nil
                grecipe.col = nil
            end
            grecipe.entity = nil
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
---@param all boolean?
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return integer
function gutils.get_product_flow(g, all)
    ---@type table<string, GProduct>
    local inputs
    ---@type table<string, GProduct>
    local outputs
    ---@type table<string, GProduct>
    local intermediates

    inputs = {}
    outputs = {}
    intermediates = {}
    local selection = g.selection
    if not selection then selection = {} end
    local recipe_count = 0
    ---@type {[string]:GRecipe}
    local recipes
    if all then
        recipes = g.recipes
    else
        recipes = g.selection
    end
    if recipes then
        for _, recipe in pairs(recipes) do
            if recipe.visible and not recipe.is_product then
                for _, ingredient in pairs(recipe.ingredients) do
                    local name = ingredient.name
                    inputs[name] = ingredient
                end
            end
            recipe_count = recipe_count + 1
        end
        for _, recipe in pairs(recipes) do
            if recipe.visible and not recipe.is_product then
                for _, product in pairs(recipe.products) do
                    local name = product.name
                    if inputs[name] then
                        intermediates[name] = product
                        inputs[name] = nil
                    elseif not intermediates[name] then
                        outputs[name] = product
                    end
                end
            end
        end
    end
    return inputs, outputs, intermediates, recipe_count
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

---@param g Graph
function gutils.fire_selection_change(g)
    tools.fire_user_event(commons.selection_change_event, { g = g })
end

---@param g Graph
function gutils.recenter(g)
    local mincol, maxcol, minline, maxline

    local count = 0
    for _, grecipe in pairs(g.recipes) do
        if grecipe.col then
            if minline then
                if grecipe.col < mincol then mincol = grecipe.col end
                if grecipe.col > maxcol then maxcol = grecipe.col end
                if grecipe.line < minline then minline = grecipe.line end
                if grecipe.line > maxline then maxline = grecipe.line end
            else
                mincol, minline = grecipe.col, grecipe.line
                maxcol, maxline = grecipe.col, grecipe.line
            end
        end
    end

    local center_col = 0
    local center_line = 0
    if minline then
        center_col = math.floor((mincol + maxcol) / 2)
        center_line = math.floor((minline + maxline) / 2)
    end

    local x, y = gutils.get_position(g, center_col, center_line)
    g.player.teleport({ x, y })
end

---@param recipes table<any, GRecipe>
function gutils.compute_sum(recipes)
    local col, line, count = 0, 0, 0
    for _, recipe in pairs(recipes) do
        if recipe.visible and recipe.col then
            col = col + recipe.col
            line = line + recipe.line
            count = count + 1
        end
    end
    return col, line, count
end

---@param container LuaGuiElement
---@param product_name string
---@param button_name string?
---@return LuaGuiElement
function gutils.create_product_button(container, product_name, button_name)
    ---@cast button_name -nil
    local b
    if string.find(product_name, "^item/") then
        b = container.add { type = "choose-elem-button", elem_type = "item", item = string.sub(product_name, 6), name = button_name }
    else
        b = container.add { type = "choose-elem-button", elem_type = "fluid", fluid = string.sub(product_name, 7), name = button_name }
    end
    b.locked = true
    return b
end

-- Fire production change
---@param g Graph
function gutils.fire_production_data_change(g)
    tools.fire_user_event(commons.production_data_change_event, { g = g })
end

---@param g Graph
---@return {[string]:GProduct}
function gutils.get_output_products(g)
    ---@type {[string]:GProduct}
    local products = {}
    for _, recipe in pairs(g.selection) do
        for _, product in pairs(recipe.products) do
            local name = product.name
            products[name] = product
        end
    end
    return products
end

local saved_graph_fields = {
    "preferred_machines",
    "preferred_modules",
    "preferred_beacon",
    "preferred_beacon_count",
    "iovalues",
    "visibility",
    "color_index"
}

local saved_reciped_fields = {
    "name",
    "production_config",
    "line",
    "col"
}

gutils.saved_graph_fields = saved_graph_fields

---@param g Graph
---@return SavingData
function gutils.create_saving_data(g)
    ---@type SavingData
    local saved = {}
    saved.config = {}
    for _, field in pairs(saved_graph_fields) do
        saved.config[field] = g[field]
    end

    saved.selection = {}
    if g.selection then
        for _, grecipe in pairs(g.selection) do
            local saved_recipe = {}
            for _, field in pairs(saved_reciped_fields) do
                saved_recipe[field] = grecipe[field]
            end
            table.insert(saved.selection, saved_recipe)
        end
    end
    saved.colors = {}
    for _, gproduct in pairs(g.products) do
        if gproduct.color then
            saved.colors[gproduct.name] = gproduct.color
        end
    end
    return saved
end

---@param g Graph
---@param products {[string]:any}
---@return {[string]:GRecipe}
function gutils.get_connected_recipes(g, products)
    ---@type {[string]:GProduct}
    local to_scan = {}
    local done_scan = {}
    for product_name, _ in pairs(products) do
        local product = g.products[product_name]
        to_scan[product_name] = product
    end

    ---@type {[string]:GRecipe}
    local connected_recipes = {}
    while (true) do
        local product_name, gproduct = next(to_scan)
        if not product_name then break end
        to_scan[product_name] = nil
        done_scan[product_name] = true
        for _, grecipe in pairs(gproduct.product_of) do
            if g.selection[grecipe.name] then
                connected_recipes[grecipe.name] = grecipe
                for _, ingredient in pairs(grecipe.ingredients) do
                    if not done_scan[ingredient.name] then
                        to_scan[ingredient.name] = ingredient
                    end
                end
            end
        end
        for _, grecipe in pairs(gproduct.ingredient_of) do
            if grecipe.is_void and g.selection[grecipe.name] then
                connected_recipes[grecipe.name] = grecipe
            end
        end
    end
    return connected_recipes
end

---@param g Graph
---@param grecipe GRecipe
---@param col integer
---@param line integer
function gutils.set_colline(g, grecipe, col, line)
    local gcol = g.gcols[grecipe.col]
    gcol.line_set[grecipe.line] = nil

    gcol = g.gcols[col]
    if not gcol then
        gcol = {
            col = col,
            line_set = {}
        }
        g.gcols[col] = gcol
    end
    grecipe.line = line
    grecipe.col = col
    gcol.line_set[line] = grecipe

    if not gcol.min_line or line < gcol.min_line then
        gcol.min_line = line
    end
    if not gcol.max_line or line > gcol.max_line then
        gcol.max_line = line
    end
end

---@param player LuaPlayer
---@param recipe_name string
function gutils.set_cursor_stack(player, recipe_name)
    player.cursor_stack.clear()
    player.cursor_stack.set_stack { name = commons.recipe_symbol_name, count = 1 }
    player.cursor_stack.tags = { recipe_name = recipe_name }
end

return gutils
