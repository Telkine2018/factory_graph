local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local colors = require("scripts.colors")
local recipe_selection = require("scripts.recipe_selection")

local graph = require("scripts.graph")
local drawing = require("scripts.drawing")

local debug = tools.debug
local prefix = commons.prefix

local command = {}

local function np(name)
    return prefix .. "-command." .. name
end

local command_frame_name = np("command")
tools.add_panel_name(command_frame_name)

command.frame_name      = command_frame_name

local select_modes      = {

    commons.none_selection,
    commons.ingredient_selection,
    commons.product_selection,
    commons.ingredient_and_product_selection
}
local select_mode_items = {}
for _, name in pairs(select_modes) do
    table.insert(select_mode_items, { np(name .. "_selection") })
end

local visibility_items = {
    { np("visibility_all") },
    { np("visibility_selection") }
}

---@param player LuaPlayer
function command.open(player)
    local player_index = player.index
    local g = gutils.get_graph(player)

    command.close(player)

    local frame = player.gui.left.add {
        type = "frame",
        direction = 'vertical',
        name = command_frame_name
    }

    --frame.style.width = 600
    --frame.style.minimal_height = 300

    local titleflow = frame.add { type = "flow" }
    local title_label = titleflow.add {
        type = "label",
        caption = { np("title") },
        style = "frame_title",
        ignored_by_interaction = true
    }

    local drag = titleflow.add {
        type = "empty-widget",
        style = "flib_titlebar_drag_handle"
    }

    local inner_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    local select_index = 1
    for i = 1, #select_modes do
        if select_modes[i] == g.select_mode then
            select_index = i
            break
        end
    end
    local hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "label", caption = { np("selection_label") } }
    hflow.add { type = "drop-down", caption = { "selection_mode" }, items = select_mode_items, selected_index = select_index, name = np("selection") }
    hflow.style.bottom_margin = 5

    local visibility = g.visibility
    if not visibility then visibility = commons.visibility_all end
    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "label", caption = { np("visibility_label") } }
    hflow.add { type = "drop-down", caption = { "visibility_mode" }, items = visibility_items, selected_index = visibility, name = np("visibility") }
    hflow.add {
        type = "sprite-button",
        name = np("refresh"),
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = prefix .. "_refresh_white",
        hovered_sprite = prefix .. "_refresh_black"
    }
    hflow.style.bottom_margin = 5

    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "button", caption = { np("search-text") }, name = np("search-text") }
    hflow.add { type = "button", caption = { np("recompute-colors") }, name = np("recompute-colors") }
end

tools.on_named_event(np("recompute-colors"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        colors.recompute_colors(g)
        drawing.update_drawing(player)
    end)

tools.on_named_event(np("search-text"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        recipe_selection.open(player, g)
    end)

tools.on_named_event(np("selection"), defines.events.on_gui_selection_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        g.select_mode = select_modes[e.element.selected_index]
    end)

---@param player any
local function refresh(player)
    local g = gutils.get_graph(player)
    if g.visibility == commons.visibility_all then
        gutils.set_full_visibility(g)
    elseif g.visibility == commons.visibility_selection then
        gutils.set_visibility_to_selection(g)
    else
        gutils.set_full_visibility(g)
    end
    drawing.delete_content(g)
    graph.do_layout(g)
    graph.draw(g)
    drawing.update_drawing(player)
end

tools.on_named_event(np("visibility"), defines.events.on_gui_selection_state_changed,
    function(e)
        local player = game.players[e.player_index]
        ---@type Graph
        local g = gutils.get_graph(player)
        g.visibility = e.element.selected_index
        refresh(player)
        player.teleport({ 0, 0 })
    end)

tools.on_named_event(np("refresh"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        refresh(player)
    end)


---@param player LuaPlayer
function command.close(player)
    local frame = player.gui.left[command_frame_name]
    if frame then
        frame.destroy()
    end
end

return command
