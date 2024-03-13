

local commons = require("scripts.commons")

local prefix = commons.prefix

data:extend(
    {
		{
			type = "int-setting",
			name = prefix .. "-version",
			setting_type = "startup",
			default_value = 1
		}

})
