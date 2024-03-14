local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local debug = tools.debug
local prefix = commons.prefix

local settings = {}

local function np(name)
    return prefix .. "-settings." .. name
end

local settings_frame_name = np("settings")
tools.add_panel_name(settings_frame_name)

---@param player LuaPlayer
---@param g Graph
---@param product GProduct
---@param src GRecipe
function settings.open(player, g, product, src)
    local player_index = player.index

    settings.close(player_index)


    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = settings_frame_name
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

    drag.drag_target = frame
    titleflow.drag_target = frame

    titleflow.add {
        type = "sprite-button",
        name = np("close"),
        tooltip = { np("close-tooltip") },
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = "utility/close_white",
        hovered_sprite = "utility/close_black"
    }

    local flow = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    local button_flow = frame.add { type = "flow", direction = "horizontal" }

    button_flow.add { type = "button", name = np("ok"), caption = { np("ok") } }
    button_flow.add { type = "button", name = np("cancel"), caption = { np("cancel") } }

    frame.force_auto_center()
end


---@param player_index integer
function settings.close(player_index)
    local player = game.players[player_index]

    local frame = player.gui.screen[settings_frame_name]
    if frame then
        frame.destroy()
    end
end



return settings