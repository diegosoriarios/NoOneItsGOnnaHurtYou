local states = require 'source.states'

require 'source.screens.main_menu'
require 'source.screens.options'
require 'source.screens.characters'
require 'source.screens.game'

function love.load()
    states.switch('game')
end

function love.update(dt)
    if states.current then
        states.current:update(dt)
    end
end

function love.draw()
    if states.current then
        states.current:draw()
    end
end

function love.keypressed(key)
    if states.current then
        states.current:keypressed(key)
    end
end

function love.keyreleased(key)
    if states.current then
        states.current:keyreleased(key)
    end
end

function love.mousepressed(x, y, button)
    if states.current then
        states.current:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if states.current then
        states.current:mousereleased(x, y, button)
    end
end