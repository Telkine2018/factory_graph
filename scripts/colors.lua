local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local colors = {}

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
function colors.create_color(h, s, l)
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
function colors.create_hcolor(h)
    return colors.create_color(h, 1, 0.5)
end

---@return Color
function colors.create_random_color()
    local h = math.random(0, 72) * 5
    return colors.create_hcolor(h)
end

---@param g Graph
---@param product GProduct
function colors.get_product_color(g, product)
    if product.color then return product.color end

    product.color = colors.create_hcolor(g.color_index)
    local color_index = g.color_index
    color_index = color_index + 95
    if color_index >= 360 then
        color_index = color_index - 360
    end
    g.color_index = color_index
    return product.color
end

---@param g Graph
function colors.recompute_colors(g)
    local visible_products = gutils.get_visible_products(g)
    local count = table_size(visible_products)
    if count == 0 then return end

    for _, product in pairs(g.products) do
        product.color = nil
    end

    local delta = 360 / count
    local h = 0
    local color_list = {}
    for i = 1, count do
        local color = colors.create_hcolor(h)
        h = h + delta
        table.insert(color_list, color)
    end
    for _, product in pairs(visible_products) do
        local rindex = math.random(1, count)
        product.color = color_list[rindex]  
        color_list[rindex]  = nil
    end
end

return colors
