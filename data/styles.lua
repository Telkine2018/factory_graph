local commons = require("scripts.commons")
local styles = data.raw["gui-style"].default
local prefix = commons.prefix

styles[prefix .. "_count_label_bottom"] = {
    type = "label_style",
    parent = "count_label",
    height = 36,
    width = 36,
    vertical_align = "bottom",
    horizontal_align = "center",
    right_padding = 2
}
styles[prefix .. "_count_label_top"] = {
    type = "label_style",
    parent = prefix .. "_count_label_bottom",
    vertical_align = "top"
}

styles[prefix .. "_count_label_center"] = {
    type = "label_style",
    parent = prefix .. "_count_label_bottom",
    vertical_align = "center"
}

styles[prefix .. "_default_table"] = {
    type = "table_style",
    odd_row_graphical_set = {
        filename = "__core__/graphics/gui.png",
        position = { 78, 18 },
        size = 1,
        opacity = 0.7,
        scale = 1
    },
    vertical_line_color = { 0, 0, 0, 1 },
    top_cell_padding = 5,
    bottom_cell_padding = 5,
    right_cell_padding = 5,
    left_cell_padding = 5

}

styles[prefix .. "_button_default"] = {
    parent = "flib_slot_button_default",
    type = "button_style",
    size = 36
}

for _, suffix in ipairs({ "default", "grey", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink" }) do
    styles[prefix .. "_small_slot_button_" .. suffix] = {
        type = "button_style",
        parent = "flib_slot_button_" .. suffix,
        size = 36,
        top_margin = 0
    }
end


styles[prefix .. "_button_missing"] = {
    parent = "flib_selected_slot_button_default",
    type = "button_style",
    size = 36
}

styles[prefix .. "_button_free"] = {
    parent = "flib_slot_button_yellow",
    type = "button_style",
    size = 36
}
