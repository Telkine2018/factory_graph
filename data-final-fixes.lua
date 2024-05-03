local commons = require("scripts.commons")

local ground_tile = table.deepcopy(data.raw["tile"]["refined-concrete"])
local outofmap = table.deepcopy(data.raw["tile"]["out-of-map"])
ground_tile.name = commons.tile_name
ground_tile.minable = nil
ground_tile.layer = 0
ground_tile.map_color = outofmap.map_color
ground_tile.variants = outofmap.variants
ground_tile.transitions_between_transitions = nil
ground_tile.trigger_effect = nil
ground_tile.empty_transitions = true
ground_tile.walking_sound = nil
ground_tile.autoplace = nil

data:extend({ ground_tile })
