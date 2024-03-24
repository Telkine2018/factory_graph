
local commons = require("scripts.commons")
local styles = data.raw["gui-style"].default
local prefix = commons.prefix

styles[prefix .. "_count_label_bottom"] = {
    type = "label_style",
    parent = "count_label",
    height = 36,
    width = 36,
    vertical_align = "bottom",
    horizontal_align = "right",
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
