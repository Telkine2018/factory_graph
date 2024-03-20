
local tools = require("scripts.tools")

---@class GContext

---@class Graph
---@field surface LuaSurface
---@field recipes {[string]:GRecipe}
---@field products {[string]:GProduct}
---@field root_products {[string]:GProduct}
---@field entity_map {[integer]:(GRecipe|GProduct)}
---@field player LuaPlayer
---@field gcols GCol[]
---@field current_col integer
---@field product_line integer
---@field selection {[string]:GElement}?
---@field graph_ids integer[]?
---@field x_routing RoutingSet
---@field y_routing RoutingSet
---@field excluded_categories {[string]:boolean}?
---@field select_mode "none" | "ingredient" | "product" | "ingredient_and_product"
---@field grid_size integer
---@field show_hidden boolean?
---@field show_only_researched boolean?
---@field color_index integer
---@field visibility integer?
---@field select_product_positions GRecipeProductPosition[]?        @ to clear selection
---@field graph_select_ids integer[]?
---@field highlighted_recipes_ids integer[]?
---@field selected_recipe GRecipe?
---@field selected_recipe_entity LuaEntity?         @ entity for selected recipe
---@field selector_product_name string?             @ selected product
---@field selector_id integer?                      @ selector rectangle id 
---@field selector_product_name_id integer?         @ selector text id
---@field rs_recipe GRecipe?                        @ recipe for product selection
---@field rs_product GProduct?                      @ product for product selection
---@field rs_location GuiLocation?
---@field product_selectors {[string]:LuaEntity}    @ product name => entity
---@field select_graph_panel LuaGuiElement?         @ panel for current recipe
---@field highlighted_recipes table<string, GRecipe>

---@class GElement
---@field name string     @ name of product or recipe
---@field unit_number integer
---@field graph_symbol_id integer
---@field entity LuaEntity?

---@class GProduct : GElement
---@field ingredient_of {[string]:GRecipe}
---@field product_of {[string]:GRecipe}
---@field is_root boolean?
---@field root_recipe GRecipe?
---@field color Color

---@class GRecipe : GElement
---@field line integer?
---@field col integer?
---@field ingredients  GProduct[]
---@field products  GProduct[]
---@field selector_positions {[string]:MapPosition}
---@field is_product boolean?
---@field visible boolean?
---@field enabled boolean?

---@class GCol
---@field col integer
---@field line_set {[integer]:GElement}  @ column => element
---@field min_line integer
---@field max_line integer

---@alias RoutingSet {[integer]:GRouting}

---@class GRoutingRange
---@field disp_index integer
---@field limit1 number
---@field limit2 number
---@field tag integer

---@class GRouting
---@field range_index integer
---@field ranges GRoutingRange[]

---@class GSavedRouting
---@field x_routing RoutingSet
---@field y_routing RoutingSet
---@field tag integer

---@class GRecipeSelection
---@field product GProduct
---@field src GRecipe

---@class GRecipeProductPosition
---@field product_name string
---@field recipe GRecipe

