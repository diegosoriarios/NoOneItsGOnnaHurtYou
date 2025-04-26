local states = require 'source.states'

local character = states.new('character')

function character:init()
    self.characters = {
        {name = "Character 1", speed = 5},
        {name = "Character 2", speed = 6},
        {name = "Character 3", speed = 4},
        {name = "Character 1", speed = 5},
        {name = "Character 2", speed = 6},
        {name = "Character 3", speed = 4},
    }
    self.selected = 1
    self.state = "character"
    self.selectedProtege = 1

    self.protege = {
        { name = "Name", image = "image"},
        { name = "Name2", image = "image2"},
    }
    
    local gridRows = 1
    local gridCols = 3
    
    local cellSize = math.min(
        love.graphics.getWidth() / (gridCols + 2),
        love.graphics.getHeight() / (gridRows + 2)
    )

    grid = {
        rows = gridRows,
        cols = gridCols,
        cellSize = cellSize,
        colors = {
            bg = {0.2, 0.2, 0.2},
            line = {1, 1, 1},
            highlight = {0.3, 0.7, 0.3, 0.3}
        }
    }
    
    grid.startX = (love.graphics.getWidth() - (grid.cellSize * grid.cols)) / 2
    grid.startY = (love.graphics.getHeight() - (grid.cellSize * grid.rows)) / 2
end

function character:drawCharacterGrid()    
    love.graphics.setColor(grid.colors.line)
    love.graphics.setLineWidth(2)
    
    for i = 0, grid.cols do
        local x = grid.startX + (i * grid.cellSize)
        love.graphics.line(x, grid.startY, x, grid.startY + (grid.rows * grid.cellSize))
    end
    
    for i = 0, grid.rows do
        local y = grid.startY + (i * grid.cellSize)
        love.graphics.line(grid.startX, y, grid.startX + (grid.cols * grid.cellSize), y)
    end
    
    for row = 1, grid.rows do
        for col = 1, grid.cols do
            local x = grid.startX + ((col-1) * grid.cellSize)
            local y = grid.startY + ((row-1) * grid.cellSize)
            
            local cellIndex = ((row-1) * grid.cols + col)
            local is_this_cell = self.selected == cellIndex
            
            if (is_this_cell) then
                love.graphics.setColor(grid.colors.highlight)
            else
                love.graphics.setColor(grid.colors.bg)
            end

            love.graphics.rectangle('fill', x, y, grid.cellSize, grid.cellSize)

            love.graphics.setColor(1, 1, 1)
            love.graphics.print(
                cellIndex,
                x + grid.cellSize/2 - 10,
                y + grid.cellSize/2 - 10
            )
        end
    end
end

function character:drawProtegeSelection()
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle('fill', 0, 0, screenWidth, screenHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Select Your Protege", screenWidth/2 - 50, screenHeight/4)
    
    local protegeWidth = 150
    local protegeHeight = 200
    local x = screenWidth / 2 - protegeWidth / 2
    local y = screenHeight / 2 - protegeHeight / 2

    love.graphics.setColor(0.3, 0.7, 0.3, 0.3)
    love.graphics.rectangle('fill', x, y, protegeWidth, protegeHeight)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.protege[self.selectedProtege].name, x + protegeWidth / 3, y + protegeHeight - 30)
  
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Use LEFT/RIGHT to select and ENTER to confirm", 
        screenWidth/2 - 150, screenHeight * 0.8)
end

function character:draw()
    if self.state == "character" then
        self:drawCharacterGrid()
    else
        self:drawProtegeSelection()
    end
end

function character:keypressed(key)
    if self.state == "character" then
        if key == "escape" then
            states.switch('mainmenu')
        end
        
        local totalCells = grid.rows * grid.cols
        
        if key == "left" then
            self.selected = self.selected - 1
            if (self.selected == 0) then
                self.selected = totalCells
            end
        end
        if key == "right" then
            self.selected = self.selected + 1
            if (self.selected > totalCells) then
                self.selected = 1
            end
        end
        if key == "down" then
            self.selected = self.selected + grid.cols
            if (self.selected > totalCells) then
                self.selected = self.selected - totalCells
            end
        end
        if key == "up" then
            self.selected = self.selected - grid.cols
            if (self.selected < 1) then
                self.selected = self.selected + totalCells
            end
        end
        if key == "return" then
            self.state = "protege"
        end
    else
        if key == "escape" then
            self.state = "character"
        end
        if key == "left" then
            self.selectedProtege = self.selectedProtege - 1
            if self.selectedProtege < 1 then
                self.selectedProtege = #self.protege
            end
        end
        if key == "right" then
            self.selectedProtege = self.selectedProtege + 1
            if self.selectedProtege > #self.protege then
                self.selectedProtege = 1
            end
        end
        if key == "return" then
            local selectedCharacter = self.characters[self.selected]
            local selectedProtege = self.protege[self.selectedProtege]
            print("Selected character: " .. selectedCharacter.name)
            print("Selected protege: " .. selectedProtege.name)
            states.switch('game')
        end
    end
end

return character