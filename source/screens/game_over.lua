local states = require 'source.states'

local game_over = states.new('gameover')

function game_over:init()
end

function game_over:update(dt)
end

function game_over:draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Game Over", 400, 200)
    love.graphics.print("Press Any key", 400, screen_height - 200)
end

function game_over:keypressed(key)
  states.switch('mainmenu')
end

return game_over