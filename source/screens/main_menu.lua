local states = require 'source.states'

local menu = states.new('mainmenu')

function menu:init()
    self.options = {
        "Play Game",
        "Options",
        "Exit"
    }
    self.selected = 1
end

function menu:update(dt)
end

function menu:draw()
    love.graphics.setColor(1, 1, 1)
    for i, option in ipairs(self.options) do
        local y = 200 + (i-1) * 40
        if i == self.selected then
            love.graphics.setColor(1, 1, 0)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.print(option, 400, y)
    end
end

function menu:keypressed(key)
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
    elseif key == "return" then
        if self.selected == 1 then
            states.switch('character')
        elseif self.selected == 2 then
            states.switch('options')
        elseif self.selected == 3 then
            love.event.quit()
        end
    end
end

return menu