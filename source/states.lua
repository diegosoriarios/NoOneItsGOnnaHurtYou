local states = {
  current = nil,
  all = {}
}

states.global = {
  selectedCharacter = nil,
  highScores = {},
  settings = {
      musicVolume = 1,
      sfxVolume = 1,
      fullscreen = false
  }
}

local State = {
  init = function(self) end,
  update = function(self, dt) end,
  draw = function(self) end,
  keypressed = function(self, key) end,
  keyreleased = function(self, key) end,
  mousepressed = function(self, x, y, button) end,
  mousereleased = function(self, x, y, button) end,
  exit = function(self) end
}

function states.new(stateName)
  states.all[stateName] = setmetatable({}, {__index = State})
  return states.all[stateName]
end

function states.switch(stateName)
  if states.current then
      states.current:exit()
  end
  states.current = states.all[stateName]
  states.current:init()
end

return states