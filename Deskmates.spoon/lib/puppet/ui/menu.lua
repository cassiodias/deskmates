-- The menu bar menu: show or hide, the commands each animation plays for, the main conversation, the screen.

local Mapping = require("puppet.model.mapping")

-- spoon: the running Deskmates, for its stage, mapping and actions.
return function(spoon)
  local mapping = spoon.mapping
  local function listed(commands) return #commands > 0 and table.concat(commands, ", ") or "no commands yet" end
  local items = {
    { title = spoon.stage.isShown and "Hide puppets" or "Show puppets", fn = function() spoon:toggle() end },
    { title = "-" },
    { title = "Animation to Commands Mapping", disabled = true },
  }
  for _, scene in ipairs(Mapping.SCENES) do
    items[#items + 1] = { title = "    " .. scene[2] .. ":  " .. listed(mapping[scene[1]]) .. "  …",
      fn = function() spoon:editScene(scene[1], scene[2]) end }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Main conversation:", disabled = true }
  for _, choice in ipairs(Mapping.CONVERSATION_CHOICES) do
    items[#items + 1] = { title = "    " .. choice[2], checked = mapping.conversation == choice[1], fn = function()
      mapping.conversation = choice[1]
      spoon:saveChoice()
    end }
  end
  items[#items + 1] = { title = "-" }
  for _, screen in ipairs(hs.screen.allScreens()) do
    items[#items + 1] = { title = "Move to " .. screen:name(), fn = function() spoon:moveToCorner(screen) end }
  end
  return items
end
