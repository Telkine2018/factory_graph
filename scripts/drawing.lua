local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local recipe_selection = require("scripts.recipe_selection")

local debug = tools.debug
local prefix = commons.prefix

local add_debug_info = false

local surface_prefix = commons.surface_prefix
local select_panel_name = prefix .. "-select-panel"

local drawing = {}
local routing_tag = 1
local default_disp_delta = 0.08
local product_disp_delta = 0.22
local product_sprite_offset = 0.11
local product_io_sprite_scale = 0.22
local recipe_font_size = 0.7

local marker_scale = 0.2
local marker_offset = marker_scale / 2

local entity_size = 1
local entity_size_middle = entity_size / 2

local sprite_arrow1 = prefix .. "-arrow1"

local select_modes = {
    "none",
    "ingredient",
    "product",
    "ingredient_and_product"
}

---@type GRecipe
local current_recipe

local null_value

---@param player_index integer
---@param product Product|Ingredient
---@return LocalisedString
---@return integer
local function get_product_label(player_index, product)
    local size = 0
    local caption = { "" }
    table.insert(caption, "[" .. product.type .. "=" .. product.name .. "]")
    size = 0
    local lname
    if product.type == "item" then
        lname = translations.get_item_name(player_index, product.name)
    else
        lname = translations.get_fluid_name(player_index, product.name)
    end
    if not lname then
        lname = product.name
    end
    table.insert(caption, " " .. lname)
    size = size + #lname + 1
    table.insert(caption, " x ")
    size = size + 3
    local s
    if product.amount then
        s = tostring(product.amount)
        size = size + #s
        table.insert(caption, s)
    elseif product.amount_min then
        s = tostring(product.amount_min)
        table.insert(caption, s)
        size = size + #s + 1
        table.insert(caption, "-")
        s = tostring(product.amount_max)
        table.insert(caption, s)
        size = size + #s
    end
    if product.probability and product.probability ~= 1 then
        s = " " .. tostring(product.probability * 100) .. "%"
        table.insert(caption, s)
        size = size + #s
    end
    return caption, size
end

---@param g Graph
local function clear_routing(g)
    g.x_routing = {}
    g.y_routing = {}
    routing_tag = 1
end


---@param g Graph
local function clear_selection(g)
    g.graph_select_ids = gutils.destroy_drawing(g.graph_select_ids)
    if g.select_product_positions then
        for _, p in pairs(g.select_product_positions) do
            p.recipe[p.product_name] = nil
        end
        g.select_product_positions = nil
    end
end

---@param routings RoutingSet
---@param range_position number
---@param limit1 number
---@param limit2 number
---@param disp_delta number?
---@return number
local function get_routing(routings, range_position, limit1, limit2, disp_delta)
    local range_index = math.floor(range_position * 2 + 0.5)
    local routing = routings[range_index]

    if limit1 > limit2 then
        limit1, limit2 = limit2, limit1
    end

    if not routing then
        routings[range_index] = {
            range_index = range_index,
            ranges = { { limit1 = limit1, limit2 = limit2, disp_index = 0, tag = routing_tag } }
        }
        return 0
    end

    local disp_index = 0
    local ranges = routing.ranges
    local running = true
    while running do
        for _, range in pairs(ranges) do
            if range.disp_index == disp_index and range.tag ~= routing_tag then
                local i1 = math.max(limit1, range.limit1)
                local i2 = math.min(limit2, range.limit2)
                if i1 <= i2 then
                    disp_index = disp_index + 1
                    goto next_disp
                end
            end
        end
        running = false
        ::next_disp::
    end

    table.insert(ranges, { limit1 = limit1, limit2 = limit2, disp_index = disp_index, tag = routing_tag })

    local disp = math.floor((disp_index + 1) / 2)
    if bit32.band(disp_index, 1) == 0 then
        disp = -disp
    end
    if not disp_delta then
        disp_delta = default_disp_delta
    end
    return disp * disp_delta
end

---@param g Graph
---@param ids integer[]
---@param product GProduct
---@param connected_recipes GProduct
---@param color Color
---@param dash boolean?
local function draw_recipe_connections(g, ids, product, connected_recipes, color, dash)
    local colmax, colmin, linemax, linemin
    local colavg = 0
    local lineavg = 0
    local product_count = 0

    local surface = g.surface
    local grid_size = g.grid_size
    local grid_middle = (grid_size - entity_size) / 2

    routing_tag = routing_tag + 1

    ---@param recipes {[string]:GRecipe}
    local function analyze_recipes(recipes)
        for _, recipe in pairs(recipes) do
            if not colmax then
                colmax = recipe.col
                colmin = recipe.col
                linemax = recipe.line
                linemin = recipe.line
            else
                if recipe.col < colmin then colmin = recipe.col end
                if recipe.col > colmax then colmax = recipe.col end
                if recipe.line < linemin then linemin = recipe.line end
                if recipe.line > linemax then linemax = recipe.line end
            end
            colavg = colavg + recipe.col
            lineavg = lineavg + recipe.line
            product_count = product_count + 1
        end
    end

    analyze_recipes(connected_recipes)

    --[[
    if product.name == "item/uranium-ore" then
        log("Wait")
    end
    ]]

    if product_count <= 1 then
        return
    end

    ---@param p1 MapPosition
    ---@param p2 MapPosition
    local function draw_line(p1, p2)
        local line_info = { surface = surface, color = color, from = p1, to = p2, width = 1 }
        if (dash) then
            line_info.dash_length = 0.05
            line_info.gap_length = 0.1
        end
        local id = rendering.draw_line(line_info)
        table.insert(ids, id)
    end

    ---@param x number
    ---@param y number
    ---@param positive boolean
    local function draw_product_h(x, y, positive)
        local x1
        if positive then
            x1 = x - marker_offset
            x = x + product_sprite_offset
        else
            x1 = x + marker_offset
            x = x - product_sprite_offset
        end
        local id = rendering.draw_sprite { surface = surface, sprite = product.name, target = { x, y },
            x_scale = product_io_sprite_scale, y_scale = product_io_sprite_scale }
        table.insert(ids, id)

        local orientation = 0

        if (positive) then
            orientation = 0
        else
            orientation = 0.5
        end
        if product.product_of[current_recipe.name] then
            orientation = 0.5 - orientation
        end
        id = rendering.draw_sprite {
            surface = surface, sprite = sprite_arrow1, target = { x1, y },
            tint = color,
            x_scale = marker_scale, y_scale = marker_scale,
            orientation = orientation }
        table.insert(ids, id)

        if not current_recipe.selector_positions then current_recipe.selector_positions = {} end
        if not current_recipe.selector_positions[product.name] then
            if g.select_product_positions then
                table.insert(g.select_product_positions, { product_name = product.name, recipe = current_recipe })
            end
            current_recipe.selector_positions[product.name] = { x, y }
        end
    end

    ---@param x number
    ---@param y number
    ---@param positive boolean
    local function draw_product_v(x, y, positive)
        local y1
        if positive then
            y1 = y - marker_offset
            y = y + product_sprite_offset
        else
            y1 = y + marker_offset
            y = y - product_sprite_offset
        end
        local id = rendering.draw_sprite { surface = surface, sprite = product.name, target = { x, y },
            x_scale = product_io_sprite_scale, y_scale = product_io_sprite_scale }
        table.insert(ids, id)

        local orientation = 0

        if (positive) then
            orientation = 0
        else
            orientation = 0.5
        end
        if product.product_of[current_recipe.name] then
            orientation = 0.5 - orientation
        end
        orientation = orientation + 0.25
        id = rendering.draw_sprite {
            surface = surface, sprite = sprite_arrow1, target = { x, y1 },
            tint = color,
            x_scale = marker_scale, y_scale = marker_scale,
            orientation = orientation }
        table.insert(ids, id)

        if not current_recipe.selector_positions then current_recipe.selector_positions = {} end
        if not current_recipe.selector_positions[product.name] then
            if g.select_product_positions then
                table.insert(g.select_product_positions, { product_name = product.name, recipe = current_recipe })
            end
            current_recipe.selector_positions[product.name] = { x, y }
        end
    end

    ---@param col integer
    ---@param line integer
    ---@return GRecipe
    local function find_recipe(col, line)
        for _, recipe in pairs(connected_recipes) do
            if recipe.line == line and recipe.col == col then
                return recipe
            end
        end
        return null_value
    end

    local middle_col = math.floor(colavg / product_count)
    local middle_line = math.floor(lineavg / product_count)

    if colmax - colmin > linemax - linemin then
        if colmax - colmin == 1 then
            local y = linemin * grid_size + entity_size_middle
            local x1 = colmin * grid_size + entity_size
            local x2 = colmax * grid_size
            local disp1 = get_routing(g.x_routing, y, x1, x2, product_disp_delta)
            y = y + disp1
            draw_line({ x1, y }, { x2, y })
            current_recipe = find_recipe(colmin, linemin)
            draw_product_h(x1, y, x1 > x2)
            current_recipe = find_recipe(colmax, linemin)
            draw_product_h(x2, y, x2 > x1)
        else
            local middle_y = grid_size * middle_line + grid_middle + entity_size
            local org_middle_y = middle_y

            local disp1 = 0
            local colmin_x = colmin * grid_size + entity_size + grid_middle
            local colmax_x = colmax * grid_size - grid_middle

            local draw_colmin_x = colmin_x + grid_size
            local draw_colmax_x = colmax_x - grid_size

            if colmax - colmin > 0 then
                disp1 = get_routing(g.x_routing, middle_y, colmin_x - grid_size, colmax_x + grid_size)
                middle_y = middle_y + disp1
            end

            local function display_line(recipes)
                for _, recipe in pairs(recipes) do
                    current_recipe = recipe
                    if recipe.line == middle_line or recipe.line == middle_line + 1 then
                        local dy, dy2
                        if recipe.line == middle_line then
                            dy = -(grid_middle + entity_size_middle)
                            dy2 = -grid_middle
                        else
                            dy = (grid_middle + entity_size_middle)
                            dy2 = grid_middle
                        end
                        if recipe.col == colmin then
                            local rx = colmin_x - grid_middle
                            local x = colmin_x
                            local y = org_middle_y + dy
                            local disp_x = get_routing(g.y_routing, x, middle_y, y)
                            local disp_y = get_routing(g.x_routing, y, x, rx, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ x, middle_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if x < draw_colmin_x then
                                draw_colmin_x = x
                            end
                            draw_product_h(rx, y, rx > x)
                        elseif recipe.col == colmax then
                            local rx = colmax_x + grid_middle
                            local x = colmax_x
                            local y = org_middle_y + dy
                            local disp_x = get_routing(g.y_routing, x, middle_y, y)
                            local disp_y = get_routing(g.x_routing, y, x, rx, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ x, middle_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if x > draw_colmax_x then
                                draw_colmax_x = x
                            end
                            draw_product_h(rx, y, rx > x)
                        else
                            local x = recipe.col * grid_size + entity_size_middle
                            local y = middle_y
                            local ry = org_middle_y + dy2
                            local disp_x = get_routing(g.y_routing, x, middle_y, ry, product_disp_delta)
                            x = x + disp_x
                            draw_line({ x, y }, { x, ry })
                            draw_product_v(x, ry, ry > y)
                        end
                    else
                        if recipe.col > middle_col then
                            local x = recipe.col * grid_size - grid_middle
                            local rx = x + grid_middle
                            local y = grid_size * recipe.line + entity_size_middle
                            local disp_x = get_routing(g.y_routing, x, middle_y, y)
                            local disp_y = get_routing(g.x_routing, y, x, rx, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ x, middle_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if x > draw_colmax_x then
                                draw_colmax_x = x
                            end
                            draw_product_h(rx, y, rx > x)
                        else
                            local x = recipe.col * grid_size + grid_middle + entity_size
                            local rx = x - grid_middle
                            local y = grid_size * recipe.line + entity_size_middle
                            local disp_x = get_routing(g.y_routing, x, middle_y, y)
                            local disp_y = get_routing(g.x_routing, y, x, rx, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ x, middle_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if x < draw_colmin_x then
                                draw_colmin_x = x
                            end
                            draw_product_h(rx, y, rx > x)
                        end
                    end
                end
            end

            display_line(connected_recipes)

            if colmax - colmin > 1 then
                draw_line({ draw_colmin_x, middle_y }, { draw_colmax_x, middle_y })
            end
        end
    else
        if linemax - linemin == 1 and colmax == colmin then
            local x = colmin * grid_size + entity_size_middle
            local y1 = linemin * grid_size + entity_size
            local y2 = linemax * grid_size
            local disp = get_routing(g.y_routing, x, y1, y2, product_disp_delta)
            x = x + disp
            draw_line({ x, y1 }, { x, y2 })
            current_recipe = find_recipe(colmin, linemin)
            draw_product_v(x, y1, y1 > y2)
            current_recipe = find_recipe(colmin, linemax)
            draw_product_v(x, y2, y2 > y1)
        else
            local middle_x = grid_size * middle_col + entity_size + grid_middle
            local org_middle_x = middle_x
            local linemin_y = linemin * grid_size + entity_size + grid_middle
            local linemax_y = linemax * grid_size - grid_middle

            local draw_linemin_y = linemin_y + grid_size
            local draw_linemax_y = linemax_y - grid_size

            if linemax - linemin > 0 then
                local disp = get_routing(g.y_routing, middle_x, linemin_y - grid_size, linemax_y + grid_size)
                middle_x = middle_x + disp
            end

            local function display_col(recipes)
                for _, recipe in pairs(recipes) do
                    current_recipe = recipe
                    if recipe.col == middle_col or recipe.col == middle_col + 1 then
                        local dx
                        local sens
                        if recipe.col == middle_col then
                            dx = -(grid_middle)
                        else
                            dx = (grid_middle)
                        end
                        if recipe.line == linemin then
                            local rx = org_middle_x + dx
                            local x = middle_x
                            local y = linemin * grid_size + entity_size_middle
                            local disp_y = get_routing(g.x_routing, y, rx, x, product_disp_delta)
                            y = y + disp_y
                            draw_line({ x, linemin_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if y < draw_linemin_y then
                                draw_linemin_y = y
                            end
                            draw_product_h(rx, y, rx > x)
                        elseif recipe.line == linemax then
                            local rx = org_middle_x + dx
                            local y = linemax * grid_size + entity_size_middle
                            local x = middle_x
                            local disp_y = get_routing(g.x_routing, y, rx, x, product_disp_delta)
                            y = y + disp_y
                            draw_line({ x, linemax_y }, { x, y })
                            draw_line({ x, y }, { rx, y })
                            if y > draw_linemax_y then
                                draw_linemax_y = y
                            end
                            draw_product_h(rx, y, rx > x)
                        else
                            local rx = org_middle_x + dx
                            local x = middle_x
                            local y = recipe.line * grid_size + entity_size_middle
                            local disp_y = get_routing(g.x_routing, y, rx, x, product_disp_delta)
                            y = y + disp_y
                            draw_line({ x, y }, { rx, y })
                            draw_product_h(rx, y, rx > x)
                        end
                    else
                        if recipe.line > middle_line then
                            local x = grid_size * recipe.col + entity_size_middle
                            local y = recipe.line * grid_size - grid_middle
                            local ry = y + grid_middle
                            local disp_y = get_routing(g.x_routing, y, middle_x, x)
                            local disp_x = get_routing(g.y_routing, x, y, ry, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ middle_x, y }, { x, y })
                            draw_line({ x, y }, { x, ry })
                            if y > draw_linemax_y then
                                draw_linemax_y = y
                            end
                            draw_product_v(x, ry, ry > y)
                        else
                            local x = grid_size * recipe.col + entity_size_middle
                            local y = recipe.line * grid_size + entity_size + grid_middle
                            local ry = y - grid_middle
                            local disp_y = get_routing(g.x_routing, y, middle_x, x)
                            local disp_x = get_routing(g.y_routing, x, y, ry, product_disp_delta)
                            x = x + disp_x
                            y = y + disp_y
                            draw_line({ middle_x, y, }, { x, y })
                            draw_line({ x, y }, { x, ry })
                            if y < draw_linemin_y then
                                draw_linemin_y = y
                            end
                            draw_product_v(x, ry, ry > y)
                        end
                    end
                end
            end

            display_col(connected_recipes)

            if linemax - linemin > 1 then
                draw_line({ middle_x, draw_linemin_y }, { middle_x, draw_linemax_y })
            end
        end
    end
    current_recipe = null_value
end

---@param g Graph
---@param ids integer[]
---@param base_recipe GRecipe
---@param product GProduct
---@param color Color
local function draw_select_product(g, ids, base_recipe, product, color)
    local connected_recipes = { base_recipe }
    local is_in_selection = g.selection[base_recipe.name]
    for _, recipe in pairs(product.product_of) do
        if not is_in_selection or not g.selection[recipe.name] then
            table.insert(connected_recipes, recipe)
        end
    end

    if #connected_recipes > 1 then
        draw_recipe_connections(g, ids, product, connected_recipes, color, true)
    end
end

---@param g Graph
local function draw_graph(g)
    clear_selection(g)

    g.graph_ids = gutils.destroy_drawing(g.graph_ids)
    if not g.selection then return end

    ---@type {[string]:{[string]:GRecipe}}
    local product_to_recipes = {}

    local ids = {}
    ---@type {[string]:GProduct}
    local ingredient_set = {}
    ---@type {[string]:GProduct}
    local product_set = {}

    for _, recipe in pairs(g.recipes) do
        recipe.selector_positions = nil
    end

    for name, o in pairs(g.selection) do
        if g.recipes[name] then
            ---@cast o GRecipe

            for _, ingredient in pairs(o.ingredients) do
                local recipes = product_to_recipes[ingredient.name]
                if not recipes then
                    recipes = { [o.name] = o }
                    product_to_recipes[ingredient.name] = recipes
                else
                    recipes[o.name] = o
                end
                ingredient_set[ingredient.name] = ingredient
            end

            for _, prod in pairs(o.products) do
                local recipes = product_to_recipes[prod.name]
                if not recipes then
                    recipes = { [o.name] = o }
                    product_to_recipes[prod.name] = recipes
                else
                    recipes[o.name] = o
                end
                product_set[prod.name] = prod
            end

            local margin = 0.6
            local grid_size = g.grid_size
            local p = { x = grid_size * o.col + 0.5, y = grid_size * o.line + 0.5 }
            id = rendering.draw_rectangle { surface = g.surface, color = { 0, 1, 0 },
                left_top = { p.x - margin, p.y - margin },
                right_bottom = { p.x + margin, p.y + margin },
                draw_on_ground = true
            }
            table.insert(ids, id)
        end
    end

    clear_routing(g)
    for product_name, recipes in pairs(product_to_recipes) do
        if table_size(recipes) > 1 and product_set[product_name] and ingredient_set[product_name] then
            local product = g.products[product_name]
            local color = gutils.get_product_color(g, product)
            draw_recipe_connections(g, ids, product, recipes, color)
        end
    end
    g.graph_ids = ids
end

---@param g Graph
---@return GSavedRouting
local function save_routings(g)
    local save = {}
    save.x_routing = tools.table_deep_copy(g.x_routing)
    save.y_routing = tools.table_deep_copy(g.y_routing)
    save.tag = routing_tag
    return save
end

---@param g Graph
---@param save  GSavedRouting
local function restore_routings(g, save)
    g.x_routing = save.x_routing
    g.y_routing = save.y_routing
    routing_tag = save.tag
    return save
end

---@param g Graph
---@param ids integer[]
---@param base_recipe GRecipe
local function draw_select_set(g, ids, base_recipe)
    if g.select_mode ~= "none" then
        local save = save_routings(g)
        if g.select_mode == "ingredient" or g.select_mode == "ingredient_and_product" then
            for _, ingredient in pairs(base_recipe.ingredients) do
                draw_select_product(g, ids, base_recipe, ingredient, gutils.get_product_color(g, ingredient))
            end
        end
        if g.select_mode == "product" or g.select_mode == "ingredient_and_product" then
            for _, product in pairs(base_recipe.products) do
                draw_select_product(g, ids, base_recipe, product, gutils.get_product_color(g, product))
            end
        end
        restore_routings(g, save)
    end
end

---@param g Graph
function drawing.next_select_mode(g)
    local mode = g.select_mode

    for i = 1, #select_modes do
        if select_modes[i] == mode then
            i = i + 1
            if i > #select_modes then
                i = 1
            end
            g.select_mode = select_modes[i]
            return
        end
    end
    g.select_mode = select_modes[1]
end

---@param player LuaPlayer
---@param entity LuaEntity
---@param grecipe GRecipe
local function draw_selected_entity(player, entity, grecipe)
    local vars = tools.get_vars(player)

    ---@type Graph
    local g = vars.graph;

    clear_selection(g)

    local ids = {}
    g.graph_select_ids = ids

    g.select_product_positions = {}
    draw_select_set(g, ids, grecipe)

    ---@type LocalisedString
    local name = translations.get_recipe_name(player.index, grecipe.name)

    local id = rendering.draw_text { surface = g.surface,
        target = entity, text = name, color = { 1, 1, 1 }, target_offset = { 0, 0.6 },
        vertical_alignment = "top", alignment = "center", scale = recipe_font_size }
    table.insert(ids, id)

    if g.product_selectors then
        for _, entity in pairs(g.product_selectors) do
            entity.destroy()
        end
        g.product_selectors = nil
    end

    if grecipe.selector_positions then
        ---@type {[string]:LuaEntity}
        local selectors = {}
        local products = gutils.product_set(grecipe)
        for product_name, _ in pairs(products) do
            local position = grecipe.selector_positions[product_name]
            if position then
                local entity = g.surface.create_entity {
                    name = commons.product_selector_name,
                    position = position,
                    force = g.player.force_index,
                    create_build_effect_smoke = false
                }
                selectors[product_name] = entity
            end
        end
        g.product_selectors = selectors
    end
end

---@param e EventData.on_selected_entity_changed
local function on_selected_entity_changed(e)
    local player_index = e.player_index
    ---@type LuaPlayer
    local player = game.players[player_index]
    local vars = tools.get_vars(player)
    local surface = player.surface

    if string.sub(surface.name, 1, #surface_prefix) ~= surface_prefix then
        return
    end

    local g = vars.graph;
    if not g then return end

    local entity = player.selected
    -- game.print("[" .. game.tick .. "] => " .. serpent.block(entity and (entity.name .. ":" .. tools.strip(entity.position)) or "null"))

    if (vars.selector_id) then
        rendering.destroy(vars.selector_id)
        vars.selector_id = nil
    end
    if entity then
        if entity.name == commons.product_selector_name then
            vars.selector_id = rendering.draw_rectangle {
                surface = surface,
                color = { 1, 0, 0 },
                left_top = entity, left_top_offset = { -commons.selector_size, -commons.selector_size },
                right_bottom = entity, right_bottom_offset = { commons.selector_size, commons.selector_size },
                width = 0.5
            }
            return
        end

        if entity.name == commons.recipe_symbol_name then
            local grecipe = g.entity_map[entity.unit_number]
            if grecipe and grecipe.name and grecipe == vars.selected_recipe then
                return
            end
        end
    end

    vars.selected_recipe = nil
    vars.selected_recipe_entity = nil

    local select_panel = player.gui.left[select_panel_name]
    if select_panel then
        select_panel.destroy()
    end

    clear_selection(g)

    if vars.select_graph_panel then
        vars.select_graph_panel.destroy()
        vars.select_graph_panel = nil
    end

    if not entity then
        return
    end

    ---@cast entity LuaEntity
    if entity.name == commons.recipe_symbol_name then
        local grecipe = g.entity_map[entity.unit_number]
        if grecipe then
            ---@type LuaRecipePrototype
            local recipe = game.recipe_prototypes[grecipe.name]
            ---@type LocalisedString
            local name = translations.get_recipe_name(player_index, grecipe.name)

            if add_debug_info then
                name = { "", name, "[", grecipe.name, "]" }
            end

            local frame = player.gui.left.add { type = "frame", caption = name }
            frame.style.width = 400
            vars.select_graph_panel = frame

            local flow = frame.add { type = "flow", direction = "vertical" }
            local max = 0
            if recipe.ingredients then
                for _, p in pairs(recipe.ingredients) do
                    local caption, size = get_product_label(player_index, p)
                    if size > max then
                        max = size
                    end
                    if add_debug_info then
                        caption = { "", caption, " [", p.name, "]" }
                    end
                    flow.add { type = "label", caption = caption }
                end
            end

            flow.add { type = "line" }
            if recipe.products then
                for _, p in pairs(recipe.products) do
                    local caption, size = get_product_label(player_index, p)
                    if size > max then
                        max = size
                    end
                    if add_debug_info then
                        caption = { "", caption, " [", p.name, "]" }
                    end
                    flow.add { type = "label", caption = caption }
                end
            end

            vars.selected_recipe = grecipe
            vars.selected_recipe_entity = entity
            draw_selected_entity(player, entity, grecipe)
        end
    end
end
tools.on_event(defines.events.on_selected_entity_changed, on_selected_entity_changed)

---@param e EventData.on_gui_opened
local function on_gui_opened(e)
    local player = game.players[e.player_index]

    local entity = e.entity
    ---@type Graph
    local g = tools.get_vars(player).graph
    if not g then return end
    if entity then
        if entity.name == commons.recipe_symbol_name then
            local grecipe = g.entity_map[entity.unit_number]
            if not grecipe then return end

            if g.selection[grecipe.name] then
                g.selection[grecipe.name] = nil
            else
                g.selection[grecipe.name] = grecipe
            end

            draw_graph(g)

            draw_selected_entity(player, entity, grecipe)

            player.opened = nil
        elseif entity.name == commons.product_symbol_name then
            player.opened = nil
        elseif entity.name == commons.product_selector_name then
            for product_name, selector in pairs(g.product_selectors) do
                if selector == entity then
                    local vars = tools.get_vars(player)
                    local grecipe = vars.selected_recipe

                    if grecipe then
                        if not g.selection[grecipe.name] then
                            g.selection[grecipe.name] = grecipe
                            draw_graph(g)
                            draw_selected_entity(player, vars.selected_recipe_entity, grecipe)
                        end
                        local product = g.products[product_name]
                        recipe_selection.open(player, g, product, grecipe)
                    end
                end
            end
            player.opened = nil
        end
    end
end
tools.on_event(defines.events.on_gui_opened, on_gui_opened)

---@param player LuaPlayer
function drawing.update_drawing(player)
    local vars = tools.get_vars(player)
    ---@type Graph
    local g = vars.graph

    clear_selection(g)
    draw_graph(g)
    if vars.selected_recipe and vars.selected_recipe_entity then
        draw_selected_entity(player, vars.selected_recipe_entity, vars.selected_recipe)
    end
end

recipe_selection.update_drawing = drawing.update_drawing

return drawing
