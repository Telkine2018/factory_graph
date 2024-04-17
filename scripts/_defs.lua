local tools = require("scripts.tools")

---@class GContext

---@class GraphRuntime
---@field surface LuaSurface
---@field player LuaPlayer
---@field recipes {[string]:GRecipe}
---@field products {[string]:GProduct}
---@field entity_map {[integer]:(GRecipe|GProduct)}
---@field gcols GCol[]
---@field current_col integer
---@field product_line integer
---@field graph_ids integer[]?
---@field x_routing RoutingSet
---@field y_routing RoutingSet
---@field select_product_positions GRecipeProductPosition[]?        @ to clear selection
---@field graph_select_ids integer[]?
---@field highlighted_recipes_ids integer[]?
---@field selected_recipe GRecipe?
---@field selected_recipe_entity LuaEntity?         @ entity for selected recipe
---@field selector_product_name string?             @ selected product
---@field product_selectors {[string]:LuaEntity}    @ product name => entity
---@field rs_recipe GRecipe?                        @ recipe for product selection
---@field rs_product GProduct?                      @ product for product selection
---@field rs_location GuiLocation?
---@field selector_id integer?                      @ selector rectangle id
---@field selector_product_name_id integer?         @ selector text id
---@field use_connected_recipes boolean
---@field product_outputs {[string]:number}
---@field product_inputs {[string]:number}
---@field production_failed LocalisedString?
---@field production_recipes_failed {[string]:boolean}
---@field total_energy number
---@field bound_products {[string]:boolean}
---@field recipe_order integer
---@field player_position MapPosition
---@field module_limitations {[string]:({[string]:true})}
---@field excluded_categories {[string]:boolean}?
---@field select_mode "none" | "ingredient" | "product" | "ingredient_and_product"
---@field grid_size integer
---@field show_hidden boolean?
---@field show_only_researched boolean?
---@field always_use_full_selection boolean?
---@field require_full_selection boolean?
---@field move_recipe GRecipe?
---@field layout_on_selection boolean?
---@field graph_zoom_level number?
---@field world_zoom_level number?

---@class GraphConfig
---@field visibility integer?
---@field selection {[string]:GRecipe}?
---@field preferred_machines string[]
---@field preferred_modules string[]
---@field preferred_beacon string?
---@field preferred_beacon_count integer
---@field iovalues {[string]:number|boolean}
---@field color_index integer

---@class Graph : GraphRuntime, GraphConfig

---@class GElement
---@field name string     @ name of product or recipe
---@field entity LuaEntity?
---@field used boolean?

---@class GProduct : GElement
---@field ingredient_of {[string]:GRecipe}
---@field product_of {[string]:GRecipe}
---@field is_root boolean?
---@field root_recipe GRecipe?
---@field color Color
---@field ids integer[]?

---@class GRecipe : GElement, GRecipeConfig, GSortNode
---@field ingredients  GProduct[]
---@field products  GProduct[]
---@field enabled boolean?
---@field selector_positions {[string]:MapPosition}
---@field is_product boolean?
---@field craft_per_s number?
---@field machine ProductionMachine?
---@field order integer?
---@field visible boolean?
---@field is_void boolean?
---@field is_recursive boolean?

---@class GSortNode
---@field sort_level integer?
---@field in_path boolean?
---@field sort_product_current integer?
---@field sort_recipe_current string?

---@class GRecipeConfig
---@field production_config ProductionConfig?
---@field line integer?
---@field col integer?

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

---@class ProductionConfig
---@field machine_name string
---@field machine_modules string[]
---@field beacon_name string?
---@field beacon_modules string[]?
---@field beacon_count integer?

---@class ProductionMachine
---@field name string
---@field grecipe GRecipe
---@field config ProductionConfig
---@field recipe LuaRecipePrototype
---@field machine LuaEntityPrototype
---@field modules LuaItemPrototype[]
---@field speed number
---@field productivity number
---@field consumption number
---@field pollution number
---@field theorical_craft_s number      @ without productivity
---@field limited_craft_s number        @ without productivity
---@field produced_craft_s number
---@field count number

---@class GraphSelectionChangeEvent
---@field g Graph

---@class Saving
---@field icon1 string?
---@field icon2 string?
---@field label string
---@field json string 

---@class SavingData
---@field config GraphConfig
---@field selection GRecipeConfig[]
---@field colors {[string]:Color}?

---@class RemoteRecipe : ProductionConfig
---@field name string

---@class RemoteConfig
---@field recipes {[string]:RemoteRecipe}

---@class RedrawRequest
---@field selection_changed boolean?
---@field do_layout boolean?
---@field center_on_recipe string
---@field center_on_graph boolean?
---@field draw_target  boolean?
