
local tools = require("scripts.tools")

---@class GContext

---@class Graph
---@field surface LuaSurface
---@field recipes {[string]:GRecipe}
---@field products {[string]:GProduct}
---@field entity_map {[integer]:(GRecipe|GProduct)}
---@field player LuaPlayer
---@field gcols GCol[]
---@field root_products {[string]:GProduct}
---@field excluded_categories {[string]:boolean}?
---@field selection {[string]:GElement}?
---@field graph_ids integer[]?
---@field x_routing RoutingSet
---@field y_routing RoutingSet
---@field select_mode "none" | "ingredient" | "product" | "ingredient_and_product"
---@field product_selectors {[string]:LuaEntity}
---@field grid_size integer
---@field color_index integer
---@field select_product_positions GRecipeProductPosition[]?        @ to clear selection
---@field graph_select_ids integer[]?

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
