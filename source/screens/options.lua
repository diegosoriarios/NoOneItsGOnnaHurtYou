local states = require 'source.states'

local options = states.new('options')

function options:init()
    self.options = {
        {name = "Music Volume", value = 100},
        {name = "SFX Volume", value = 100},
        {name = "Fullscreen", value = false},
        {name = "Save", value = nil},
    }
    self.selected = 1
end

function options:draw()
    local start_y = 200
    love.graphics.setColor(1, 1, 1)
    for i, option in ipairs(self.options) do
        local y = start_y + (i-1) * 40
        if i == self.selected then
            love.graphics.setColor(1, 1, 0)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.print(option.name, 400, y)
        if type(option.value) == "boolean" then
            love.graphics.print(option.value == true and "Yes" or "No", 600, y)
        elseif type(option.value) == "number" then
            love.graphics.print(option.value, 600, y)
        end
    end
end

function options:keypressed(key)
    if key == "escape" then
        states.switch('mainmenu')
    end

    if key == "return" then
        if self.selected == 4 then
            love.window.setFullscreen(self.options[3].value, "desktop")
            states.switch('mainmenu')
        end
    end

    if key == "left" then
        if self.selected == 3 then
            self.options[3].value = not self.options[3].value
            return
        elseif self.selected == 4 then
            return
        end
        
        self.options[self.selected].value = self.options[self.selected].value - 1
        if self.options[self.selected].value < 0 then
            self.options[self.selected].value = 0
        end
    end

    if key == "right" then
        if self.selected == 3 then
            self.options[3].value = not self.options[3].value
            return
        elseif self.selected == 4 then
            return
        end
        
        self.options[self.selected].value = self.options[self.selected].value + 1
        if self.options[self.selected].value > 100 then
            self.options[self.selected].value = 100
        end
    end

    if key == "up" then
        self.selected = self.selected - 1
        if self.selected < 1 then 
            self.selected = #self.options 
        end
    elseif key == "down" then
        self.selected = self.selected + 1
        if self.selected > #self.options then 
            self.selected = 1 
        end
    end
end

return options