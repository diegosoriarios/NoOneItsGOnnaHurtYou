function generateAttacks()
  local attacks = {
    [0] = {
      name = "Circle Attack",
      radius = 50,
      duration = 0.5,
      timer = 0,
      isActive = false,

      update = function(self, dt, player, enemies, bpm)
        self.timer = self.timer + dt

        if self.timer >= player.cooldown then
          self.timer = self.timer - player.cooldown
          self.isActive = true
          -- Play sound effect here if needed
        end
        if self.isActive then
          for i = #enemies, 1, -1 do
            local enemy = enemies[i]
            local dx = enemy.x - player.x
            local dy = enemy.y - player.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= self.radius then
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(10)
              table.remove(enemies, i)
              player.xp = player.xp + (1 * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end
          if self.timer >= self.duration then
            self.isActive = false
          end
        end
      end,

      draw = function(self, player)
        if self.isActive then
          love.graphics.setColor(1, 1, 1, 0.5)
          love.graphics.circle('fill', player.x, player.y, self.radius)
          love.graphics.setColor(1, 1, 1, 0.8)
          love.graphics.circle('line', player.x, player.y, self.radius)
        end

        -- Draw cooldown bar - maybe remove
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 20
        
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        love.graphics.setColor(0, 1, 1)
        local progress = (player.cooldown - self.timer) / player.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)
      end,

      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
        player.bpm = newBPM
      end
    },
    [1] = {
      name = "Radial Attack",
      bullets = {},
      radius = 5,
      bulletSpeed = 200,
      bulletCount = 8,
      cooldown = 60 / 60,
      timer = 0,

      update = function(self, dt, player, enemies)
        for i = #self.bullets, 1, -1 do
          local bullet = self.bullets[i]
          bullet.x = bullet.x + bullet.dx * self.bulletSpeed * dt
          bullet.y = bullet.y + bullet.dy * self.bulletSpeed * dt
          if bullet.x < 0 or bullet.x > screen_width or
              bullet.y < 0 or bullet.y > screen_height then
            table.remove(self.bullets, i)
          end
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - bullet.x
            local dy = enemy.y - bullet.y
            if dx * dx + dy * dy < 100 then
              table.remove(enemies, j)
              table.remove(self.bullets, i)
              player.xp = player.xp + (1 * (player.xpMultiplier or 1))
              checkLevelUp()
              break
            end
          end
        end

        self.timer = self.timer + dt
        if self.timer >= player.cooldown then
          self.timer = self.timer - player.cooldown
          for i = 1, self.bulletCount do
            local angle = (i - 1) * (2 * math.pi / self.bulletCount)
            table.insert(self.bullets, {
              x = player.x,
              y = player.y,
              dx = math.cos(angle),
              dy = math.sin(angle)
            })
          end
        end
      end,

      draw = function(self, player)
        love.graphics.setColor(1, 0.5, 0)
        for _, bullet in ipairs(self.bullets) do
          love.graphics.circle('fill', bullet.x, bullet.y, self.radius)
        end
      end,

      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
        player.bpm = newBPM
      end
    }
  }
  return attacks
end
