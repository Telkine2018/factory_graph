
local dictionary = require("__flib__/dictionary-lite")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local debug = tools.debug
local prefix = commons.prefix

local graph = require("scripts.graph")

local surface_prefix = commons.surface_prefix
local recipe_symbol_name = prefix .. "-recipe-symbol"

local switch_button_name = prefix .. "-switch"

local excluded_categories = {

     stacking = true, 
     unstacking = true,
     barrelling = true,
     ["barreling-pump"] = true,
     
     -- Creative mod
    ["creative-mod_free-fluids"] = true,
    ["creative-mod_energy-absorption"] = true,

    -- Editor extensions
    ["ee-testing-tool"] = true,

    -- Deep storage unit
    ["deep-storage-item"] = true,
    ["deep-storage-fluid"] = true,
    ["deep-storage-item-big"] = true,
    ["deep-storage-fluid-big"] = true,
    ["deep-storage-item-mk2/3"] = true,
    ["deep-storage-fluid-mk2/3"] = true,

    -- Krastorio 2
    ["void-crushing"] = true, -- This doesn't actually exist yet, but will soon!
    -- Mining drones
    ["mining-depot"] = true,
        -- Pyanodon's
    ["py-incineration"] = true,
    ["py-runoff"] = true,
    ["py-venting"] = true,
    -- Reverse factory
    ["recycle-intermediates"] = true,
    ["recycle-productivity"] = true,
    ["recycle-products"] = true,
    ["recycle-with-fluids"] = true,
    -- Transport drones
    ["fuel-depot"] = true,
    ["transport-drone-request"] = true,
    ["transport-fluid-request"] = true,
    
}

---@param e EventData.on_lua_shortcut
local function test_surface(e)
    local player = game.players[e.player_index]
    local character = player.character

    if character then

        if not player.gui.left[switch_button_name] then
            player.gui.left.add {type="button", name=switch_button_name, caption="Grapher"}
        end
        local surface = graph.enter(player)

        local g = graph.new(surface)
        g.player = player
        tools.get_vars(player).graph = g
        local recipes = game.recipe_prototypes
        graph.add_recipes(g, recipes, excluded_categories)
        graph.do_layout(g)
        graph.draw(g)
    else
        graph.exit(player)
    end
end
script.on_event(prefix .. "-alt_k", test_surface)

tools.on_gui_click(switch_button_name, test_surface)

---@param e EventData.on_lua_shortcut
local function test_click(e)
    local player = game.players[e.player_index]
    local surface = player.surface

    if string.sub(surface.name, 1, #surface_prefix) ~= surface_prefix then
        return
    end

    -- player.print("test_click:" .. game.tick)
end
script.on_event(prefix .. "-click", test_click)


