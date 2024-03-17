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

add({
  type = "custom-input",
  name = modname .. "-alt_l",
  key_sequence = "ALT + L",
  consuming = "none"
})

add({
  type = "custom-input",
  key_sequence = "mouse-button-1",
  name = prefix .. "-click"
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
  entity.minable = nil
  entity.next_upgrade = nil

  entity.name = name
  add(entity)
  return entity
end

create_symbol(commons.product_symbol_name, png("entity/product-symbol/product-symbol"))
local entity = create_symbol(commons.recipe_symbol_name, png("entity/recipe-symbol/recipe-symbol"))

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


data:extend(declarations)

