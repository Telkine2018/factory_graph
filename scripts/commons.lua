local tools = require("scripts.tools")

local prefix = "factory_graph"
local modpath = "__factory_graph__"

local commons = {

    debug_version = 2,
    modpath = modpath,
    graphic_path = modpath .. '/graphics/%s.png',
    context_version = 1,
    prefix = prefix,
    surface_prefix = "_factory_graph_",
    tile_name = prefix .. "-ground",

    recipe_symbol_name = prefix .. "-recipe-symbol",
    product_symbol_name = prefix .. "-product-symbol",
    unresearched_symbol_name = prefix .. "-unresearched-symbol",
    product_selector_name = prefix .. "-product-selector",

    selector_size = 0.1,
    grid_size = 3,

    ingredient_and_product_selection = "ingredient_and_product",
    ingredient_selection = "ingredient",
    product_selection = "product",
    none_selection = "none",

    visibility_all = 1,
    visibility_selection = 2,
    add_debug_info = false
}

commons.default_selection = commons.ingredient_and_product_selection
commons.surface_prefix_filter = "^" .. commons.surface_prefix

---@param name string
---@return string
function commons.png(name) return (commons.graphic_path):format(name) end

return commons

