local commons = require("scripts.commons")
local tools = require("scripts.tools")
local prefix = commons.prefix
local png = commons.png

local empty_sprite = {
  filename = png('invisible'),
  width = 1,
  height = 1,
  frame_count = 1
}

local declarations = {}
local function add(def) table.insert(declarations, def) end

local modname = commons.prefix

add({
  type = "custom-input",
  name = modname .. "-alt_k",
  key_sequence = "ALT + K",
  consuming = "none"
})

--[[
add({
  type = "custom-input",
  name = modname .. "-alt_l",
  key_sequence = "ALT + L",
  consuming = "none"
})
--]]

add({
  type = "custom-input",
  key_sequence = "CONTROL + mouse-button-1",
  name = prefix .. "-control-click"
})

---------------------------------------------
local function create_symbol(name, filename)
  local entity = table.deepcopy(data.raw["container"]["iron-chest"])
  entity.picture = {
    layers = {
      {
        filename = filename,
        height = 32,
        width = 32
      }
    }
  }
  local selection_size = 0.7
  entity.selection_box = {
    {
      -selection_size,
      -selection_size
    },
    {
      selection_size,
      selection_size
    },
    selection_priority = 60
  }
  entity.minable = {
    mining_time = 0.1,
    result = name,
    count = 1
  }
  entity.next_upgrade = nil
  entity.flags = { "not-in-made-in", "player-creation" }

  entity.name = name
  add(entity)
  return entity
end

create_symbol(commons.product_symbol_name, png("entity/product-symbol/product-symbol"))
create_symbol(commons.recipe_symbol_name, png("entity/recipe-symbol/recipe-symbol"))
create_symbol(commons.unresearched_symbol_name, png("entity/unresearched-symbol/unresearched-symbol"))

add({
  type = "sprite",
  name = prefix .. "-arrow1",
  filename = png("arrow1"),
  width = 32,
  height = 32
})

local selector_size = commons.selector_size

local lamp = data.raw["lamp"]["small-lamp"]

local product_selector = {

  type = "lamp",
  name = commons.product_selector_name,
  collision_box = { { -selector_size, -selector_size }, { selector_size, selector_size } },
  collision_mask = {},
  selection_box = { { -selector_size, -selector_size }, { selector_size, selector_size } },
  selection_priority = 70,
  minable = nil,
  maximum_wire_distance = 1,
  max_health = 10,
  flags = { "placeable-off-grid", "placeable-neutral", "player-creation" },
  circuit_wire_max_distance = 1,
  icon_size = lamp.icon_size,
  icon = lamp.icon,
  picture_on = empty_sprite,
  picture_off = empty_sprite,
  energy_source = { type = "void" },
  energy_usage_per_tick = "1J"
}
add(product_selector)

local sprite = {
  type = "sprite",
  name = prefix .. "_down",
  filename = png("down"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_sep",
  filename = png("sep"),
  width = 128,
  height = 16
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_arrow",
  filename = png("arrow"),
  width = 16,
  height = 16
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_arrow-white",
  filename = png("arrow-white"),
  width = 16,
  height = 16
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_refresh_black",
  filename = png("refresh_black"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_refresh_white",
  filename = png("refresh_white"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_switch",
  filename = png("switch"),
  width = 40,
  height = 40
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_mini_white",
  filename = png("mini_white"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_mini_black",
  filename = png("mini_black"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_maxi_white",
  filename = png("maxi_white"),
  width = 32,
  height = 32
}
add(sprite)

sprite = {
  type = "sprite",
  name = prefix .. "_maxi_black",
  filename = png("maxi_black"),
  width = 32,
  height = 32
}
add(sprite)

add {
  type = "sprite",
  name = prefix .. "_backward-black",
  filename = png("backward-black"),
  width = 32,
  height = 32
}

add {
  type = "sprite",
  name = prefix .. "_backward-white",
  filename = png("backward-white"),
  width = 32,
  height = 32
}

add {
  type = "sprite",
  name = prefix .. "_forward-black",
  filename = png("forward-black"),
  width = 32,
  height = 32
}

add {
  type = "sprite",
  name = prefix .. "_forward-white",
  filename = png("forward-white"),
  width = 32,
  height = 32
}

add {
  type = "custom-input",
  name = prefix .. "-up",
  key_sequence = "SHIFT + UP"
}

add {
  type = "custom-input",
  name = prefix .. "-left",
  key_sequence = "SHIFT + LEFT"
}

add {
  type = "custom-input",
  name = prefix .. "-down",
  key_sequence = "SHIFT + DOWN"
}

add {
  type = "custom-input",
  name = prefix .. "-right",
  key_sequence = "SHIFT + RIGHT"
}

add {
  type = "custom-input",
  name = prefix .. "-del",
  key_sequence = "DELETE"
}

add {
  name = commons.recipe_symbol_name,
  type = "item-with-tags",
  stack_size = 1,
  icon = png("item/recipe-symbol"),
  icon_size = 32,
  place_result = commons.recipe_symbol_name,
  flags = { "hidden", "not-stackable", "only-in-cursor" }
}

add {
  name = commons.product_symbol_name,
  type = "item-with-tags",
  stack_size = 1,
  icon = png("item/product-symbol"),
  icon_size = 32,
  place_result = commons.product_symbol_name,
  flags = { "hidden", "not-stackable", "only-in-cursor" }
}

add {
  name = commons.unresearched_symbol_name,
  type = "item-with-tags",
  stack_size = 1,
  icon = png("item/unresearched-symbol"),
  icon_size = 32,
  place_result = commons.unresearched_symbol_name,
  flags = { "hidden", "not-stackable", "only-in-cursor" }
}

add {

  type = "selection-tool",
  name = prefix .. "-selection_tool",
  icon = png("icon32"),
  icon_size = 32,
  selection_color = { r = 0, g = 0, b = 1 },
  alt_selection_color = { r = 1, g = 0, b = 0 },
  selection_mode = { "same-force", "any-entity" },
  alt_selection_mode = { "same-force", "any-entity" },
  selection_cursor_box_type = "entity",
  alt_selection_cursor_box_type = "entity",
  flags = { "hidden", "not-stackable", "only-in-cursor", "spawnable" },
  subgroup = "other",
  stack_size = 1,
  stackable = false,
  show_in_library = false,
  entity_type_filters = { "assembling-machine", "furnace" },
  alt_entity_type_filters = { "assembling-machine", "furnace" }
}

data:extend(declarations)
