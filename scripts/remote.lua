local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local graph = require("scripts.graph")
local main = require("scripts.main")
local saving = require("scripts.saving")

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
    gutils.fire_selection_change(g)
end

remote.add_interface(prefix, {
    add_recipes = add_recipes
})

commands.add_command(prefix .. "_speed", nil, function(command)
    if command.player_index ~= nil then
        local player = game.players[command.player_index]
        local vars = tools.get_vars(player)
        vars.character_speed = not vars.character_speed
        main.set_speed(player, vars.character_speed)
        saving.clear_current(player)
        if vars.character_speed then
            player.print("Speed on")
        else
            player.print("Speed off")
        end
    end
end)
