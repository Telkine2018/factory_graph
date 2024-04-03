local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local graph = require("scripts.graph")
local main = require("scripts.main")

local prefix = commons.prefix

---@param player_index integer
---@param remoteConfig RemoteConfig
local function add_recipes(player_index, remoteConfig)
    local player = game.players[player_index]

    main.enter(player)

    if not remoteConfig.recipes then
        return
    end

    local g = gutils.get_graph(player)

    for name, recipe in pairs(remoteConfig.recipes) do
        local grecipe = g.recipes[name]
        if grecipe then
            g.selection[name] = grecipe
        end
    end

    graph.refresh(player)
end

remote.add_interface(prefix, {
    add_recipes = add_recipes
})
