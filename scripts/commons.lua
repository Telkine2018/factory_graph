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
    tile_name = prefix .. "-ground2",

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
    visibility_layers = 3,
    add_debug_info = false,

    selection_change_event = "selection_change",
    production_compute_event = "production_compute",
    production_data_change_event = "production_data_change",
    graph_selection_change_event = "graph_selection_change",
    open_recipe_selection = "open_recipe_selection",

    math_precision = 0.000001,
    production_failures = {

        linear_dependecy = "linear_dependecy",
        no_soluce = "no_soluce",
        no_soluce1 = "no_soluce1",
        invalid_soluce = "invalid_soluce",
        too_many_free_variables = "too_many_free_variables",
        too_many_constraints = "too_many_constraints",
        cannot_find_machine = "cannot_find_machine",
        use_handcraft_recipe = "use_handcraft_recipe"
    },
    generate_with_lab_tiles = true

}

commons.buttons = {
    orange = prefix .. "_small_slot_button_orange",
    green = prefix .. "_small_slot_button_green",
    cyan = prefix .. "_small_slot_button_cyan",
    red = prefix .. "_small_slot_button_red",
    blue = prefix .. "_small_slot_button_blue",
    yellow = prefix .. "_small_slot_button_yellow",
    default = prefix .. "_small_slot_button_default"
}

commons.buttons.ingredient = commons.buttons.cyan
commons.buttons.product = commons.buttons.orange
commons.buttons.recipe = commons.buttons.blue

commons.default_selection = commons.ingredient_and_product_selection
commons.surface_prefix_filter = "^" .. commons.surface_prefix

---@param name string
---@return string
function commons.png(name) return (commons.graphic_path):format(name) end

return commons
