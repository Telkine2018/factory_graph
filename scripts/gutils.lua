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

---@param player LuaPlayer
---@param grecipe GRecipe
---@return LocalisedString
function gutils.get_recipe_name(player, grecipe)
    ---@type LocalisedString
    local localised_name

    if grecipe.is_product then
        if tools.starts_with(grecipe.name, "item/") then
            localised_name = translations.get_item_name(player.index, string.sub(grecipe.name, 6))
        else -- fluid
            localised_name = translations.get_fluid_name(player.index, string.sub(grecipe.name, 7))
        end
    else
        localised_name = translations.get_recipe_name(player.index, grecipe.name)
    end
    return localised_name
end

return gutils
