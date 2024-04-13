local commons = require("scripts.commons")

local ground_tile = table.deepcopy(data.raw["tile"]["grass-1"])
local outofmap = table.deepcopy(data.raw["tile"]["out-of-map"])
ground_tile.name = commons.tile_name
ground_tile.minable = nil
ground_tile.layer = 0
ground_tile.map_color = outofmap.map_color
ground_tile.variants = outofmap.variants
ground_tile.transitions = nil
ground_tile.transitions_between_transitions = nil
ground_tile.trigger_effect = nil
ground_tile.empty_transitions = true
ground_tile.walking_sound = nil
ground_tile.allowed_neighbors = { commons.tile_name }
ground_tile.autoplace = {
    probability_expression = {
        arguments = {
            {
                arguments = {
                    {
                        arguments = {
                            {
                                literal_value = -1 / 0 --[[-math.huge]],
                                type = "literal-number"
                            },
                            {
                                arguments = {
                                    {
                                        arguments = {
                                            {
                                                arguments = {
                                                    {
                                                        arguments = {
                                                            {
                                                                arguments = {
                                                                    {
                                                                        literal_value = 5.1500000000000004,
                                                                        type = "literal-number"
                                                                    },
                                                                    {
                                                                        arguments = {
                                                                            {
                                                                                arguments = {
                                                                                    {
                                                                                        type = "variable",
                                                                                        variable_name = "moisture"
                                                                                    },
                                                                                    {
                                                                                        literal_value = 5.8499999999999996,
                                                                                        type = "literal-number"
                                                                                    }
                                                                                },
                                                                                function_name = "subtract",
                                                                                type = "function-application"
                                                                            },
                                                                            {
                                                                                literal_value = 0,
                                                                                type = "literal-number"
                                                                            },
                                                                            {
                                                                                literal_value = 1 / 0 --[[math.huge]],
                                                                                type = "literal-number"
                                                                            }
                                                                        },
                                                                        function_name = "ridge",
                                                                        type = "function-application"
                                                                    }
                                                                },
                                                                function_name = "subtract",
                                                                type = "function-application"
                                                            },
                                                            {
                                                                literal_value = 20,
                                                                type = "literal-number"
                                                            }
                                                        },
                                                        function_name = "multiply",
                                                        type = "function-application"
                                                    },
                                                    {
                                                        literal_value = -1 / 0 --[[-math.huge]],
                                                        type = "literal-number"
                                                    },
                                                    {
                                                        literal_value = 1,
                                                        type = "literal-number"
                                                    }
                                                },
                                                function_name = "clamp",
                                                type = "function-application"
                                            },
                                            {
                                                literal_value = 1,
                                                type = "literal-number"
                                            }
                                        },
                                        function_name = "multiply",
                                        type = "function-application"
                                    },
                                    {
                                        literal_value = -1 / 0 --[[-math.huge]],
                                        type = "literal-number"
                                    },
                                    {
                                        arguments = {
                                            {
                                                arguments = {
                                                    {
                                                        arguments = {
                                                            {
                                                                arguments = {
                                                                    {
                                                                        literal_value = 10.5,
                                                                        type = "literal-number"
                                                                    },
                                                                    {
                                                                        arguments = {
                                                                            {
                                                                                arguments = {
                                                                                    {
                                                                                        type = "variable",
                                                                                        variable_name = "aux"
                                                                                    },
                                                                                    {
                                                                                        literal_value = 0.5,
                                                                                        type = "literal-number"
                                                                                    }
                                                                                },
                                                                                function_name = "subtract",
                                                                                type = "function-application"
                                                                            },
                                                                            {
                                                                                literal_value = 0,
                                                                                type = "literal-number"
                                                                            },
                                                                            {
                                                                                literal_value = 1 / 0 --[[math.huge]],
                                                                                type = "literal-number"
                                                                            }
                                                                        },
                                                                        function_name = "ridge",
                                                                        type = "function-application"
                                                                    }
                                                                },
                                                                function_name = "subtract",
                                                                type = "function-application"
                                                            },
                                                            {
                                                                literal_value = 20,
                                                                type = "literal-number"
                                                            }
                                                        },
                                                        function_name = "multiply",
                                                        type = "function-application"
                                                    },
                                                    {
                                                        literal_value = -1 / 0 --[[-math.huge]],
                                                        type = "literal-number"
                                                    },
                                                    {
                                                        literal_value = 1,
                                                        type = "literal-number"
                                                    }
                                                },
                                                function_name = "clamp",
                                                type = "function-application"
                                            },
                                            {
                                                literal_value = 1,
                                                type = "literal-number"
                                            }
                                        },
                                        function_name = "multiply",
                                        type = "function-application"
                                    }
                                },
                                function_name = "clamp",
                                type = "function-application"
                            },
                            {
                                literal_value = 1 / 0 --[[math.huge]],
                                type = "literal-number"
                            }
                        },
                        function_name = "clamp",
                        type = "function-application"
                    },
                    {
                        arguments = {
                            input_scale = {
                                arguments = {
                                    {
                                        literal_value = 1,
                                        type = "literal-number"
                                    },
                                    {
                                        literal_value = 6,
                                        type = "literal-number"
                                    }
                                },
                                function_name = "divide",
                                type = "function-application"
                            },
                            octaves = {
                                literal_value = 4,
                                type = "literal-number"
                            },
                            output_scale = {
                                literal_value = 0.66666666666666661,
                                type = "literal-number"
                            },
                            persistence = {
                                literal_value = 0.7,
                                type = "literal-number"
                            },
                            seed0 = {
                                type = "variable",
                                variable_name = "map_seed"
                            },
                            seed1 = {
                                arguments = {
                                    {
                                        literal_value = "grass-1",
                                        type = "literal-string"
                                    }
                                },
                                function_name = "noise-layer-name-to-id",
                                type = "function-application"
                            },
                            x = {
                                type = "variable",
                                variable_name = "x"
                            },
                            y = {
                                type = "variable",
                                variable_name = "y"
                            }
                        },
                        function_name = "factorio-multioctave-noise",
                        type = "function-application"
                    }
                },
                function_name = "add",
                type = "function-application"
            },
            {
                literal_value = 0,
                type = "literal-number"
            }
        },
        function_name = "add",
        type = "function-application"
    }
}

data:extend({ ground_tile })
