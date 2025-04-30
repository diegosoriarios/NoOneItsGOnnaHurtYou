function generateAttacks()
  local attacks = {
    [0] = {
      name = "Circle Attack",
      radius = 50,
      duration = 0.5,
      timer = 0,
      count = 0,
      isActive = false,

      update = function(self, dt, player, enemies)
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
      count = 2,
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
          for i = 1, self.count do
            local angle = (i - 1) * (2 * math.pi / self.count)
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
    },
    [2] = {
      name = "Random Circle Attack",
      radius = 50,
      duration = 0.5,
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      circles = {},       -- Store active circles
      count = 3,          -- Number of circles to spawn each time

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new attack when cooldown is reached
        if self.timer >= player.cooldown then
          self.timer = self.timer - player.cooldown

          -- Create multiple new circles at random positions
          for i = 1, self.count do
            table.insert(self.circles, {
              x = love.math.random(100, love.graphics.getWidth() - 100),
              y = love.math.random(100, love.graphics.getHeight() - 100),
              lifetime = 0,
              alpha = 1
            })
          end
        end

        -- Update existing circles
        for i = #self.circles, 1, -1 do
          local circle = self.circles[i]
          circle.lifetime = circle.lifetime + dt
          circle.alpha = 1 - (circle.lifetime / self.duration)

          -- Check for enemies in circle range
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - circle.x
            local dy = enemy.y - circle.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= self.radius then
              -- Create particle effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(10)
              -- Remove enemy
              table.remove(enemies, j)
              -- Add XP
              player.xp = player.xp + (1 * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Remove circle if duration expired
          if circle.lifetime >= self.duration then
            table.remove(self.circles, i)
          end
        end
      end,

      draw = function(self, player)
        -- Draw all active circles
        for _, circle in ipairs(self.circles) do
          -- Draw filled circle
          love.graphics.setColor(1, 0.5, 0, circle.alpha * 0.5)
          love.graphics.circle('fill', circle.x, circle.y, self.radius)
          -- Draw border
          love.graphics.setColor(1, 0.5, 0, circle.alpha)
          love.graphics.circle('line', circle.x, circle.y, self.radius)
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 40 -- Position above other bar
        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)
        -- Progress
        love.graphics.setColor(1, 0.5, 0)
        local progress = (player.cooldown - self.timer) / player.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw count indicator
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Circles: " .. self.count, barX + barWidth + 10, barY)
      end,

      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
      end
    },
    [3] = {
      name = "Boomerang Attack",
      radius = 15,               -- Size of the boomerang
      speed = 400,               -- Speed of the boomerang
      maxDistance = 300,         -- Maximum distance before returning
      cooldown = 60 / 60,        -- 60/bpm
      timer = 0,
      boomerangs = {},           -- List of active boomerangs
      count = 2,                 -- Number of boomerangs to spawn
      damage = 1,                -- Damage multiplier
      spreadAngle = math.pi / 4, -- Angle between multiple boomerangs

      update = function(self, dt, player, enemies)
        -- Update attack timer only if no boomerangs are active
        if #self.boomerangs < self.count then
          self.timer = self.timer + dt
        end

        -- Start new attack when cooldown is reached and no boomerangs are active
        if self.timer >= player.cooldown and #self.boomerangs < self.count then
          self.timer = self.timer - player.cooldown

          -- Calculate base angle from player's rotation
          local baseAngle = shipAngle

          -- Calculate spread for multiple boomerangs
          local totalSpread = self.spreadAngle * (self.count - 1)
          local startAngle = baseAngle - totalSpread / 2

          -- Spawn multiple boomerangs
          for i = 1, math.abs(self.count - #self.boomerangs) do
            local angle = startAngle + (i - 1) * self.spreadAngle

            -- Create new boomerang
            table.insert(self.boomerangs, {
              x = player.x,
              y = player.y,
              angle = angle,
              distance = 0,
              goingOut = true,
              rotation = 0,
              hitEnemies = {} -- Track hit enemies to prevent multiple hits
            })
          end
        end

        -- Update all active boomerangs
        for i = #self.boomerangs, 1, -1 do
          local boomerang = self.boomerangs[i]

          -- Update boomerang rotation for visual effect
          boomerang.rotation = boomerang.rotation + dt * 10

          if boomerang.goingOut then
            -- Moving away from player
            local dx = math.cos(boomerang.angle) * self.speed * dt
            local dy = math.sin(boomerang.angle) * self.speed * dt

            boomerang.x = boomerang.x + dx
            boomerang.y = boomerang.y + dy

            boomerang.distance = boomerang.distance + (self.speed * dt)

            -- Check if max distance reached
            if boomerang.distance >= self.maxDistance then
              boomerang.goingOut = false
            end
          else
            -- Returning to player
            local dx = player.x - boomerang.x
            local dy = player.y - boomerang.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- Normalize direction and apply speed
            if dist > 0 then
              dx = dx / dist * self.speed * dt
              dy = dy / dist * self.speed * dt
            end

            boomerang.x = boomerang.x + dx
            boomerang.y = boomerang.y + dy

            -- Check if returned to player
            if dist < 10 then
              table.remove(self.boomerangs, i)
            end
          end

          -- Check for enemy collisions
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - boomerang.x
            local dy = enemy.y - boomerang.y
            local distance = math.sqrt(dx * dx + dy * dy)

            -- Check if enemy hasn't been hit by this boomerang yet
            if distance <= self.radius + 5 and
                not boomerang.hitEnemies[j] then
              -- Mark enemy as hit
              boomerang.hitEnemies[j] = true

              -- Create particle effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(10)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end
        end
      end,

      draw = function(self, player)
        -- Draw all active boomerangs
        for _, boomerang in ipairs(self.boomerangs) do
          love.graphics.push()
          love.graphics.translate(boomerang.x, boomerang.y)
          love.graphics.rotate(boomerang.rotation)

          -- Draw boomerang shape
          love.graphics.setColor(1, 0.7, 0.2)
          love.graphics.polygon('fill',
            -self.radius, -self.radius / 2,
            self.radius, -self.radius / 2,
            self.radius / 2, self.radius,
            -self.radius / 2, self.radius
          )

          -- Draw outline
          love.graphics.setColor(1, 0.8, 0.3)
          love.graphics.polygon('line',
            -self.radius, -self.radius / 2,
            self.radius, -self.radius / 2,
            self.radius / 2, self.radius,
            -self.radius / 2, self.radius
          )

          love.graphics.pop()

          -- Draw return path (optional visual guide)
          if not boomerang.goingOut then
            love.graphics.setColor(1, 0.7, 0.2, 0.2)
            love.graphics.line(boomerang.x, boomerang.y, player.x, player.y)
          end
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 60

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        if #self.boomerangs == 0 then
          love.graphics.setColor(1, 0.7, 0.2)
          local progress = (player.cooldown - self.timer) / player.cooldown
          love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)
        else
          -- Show different color when boomerangs are active
          love.graphics.setColor(0.7, 0.5, 0.1)
          love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)
        end

        -- Draw count indicator
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Boomerangs: " .. self.count, barX + barWidth + 10, barY)
      end,

      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
        player.bpm = newBPM
      end
    },
    [4] = {
      name = "Fire Tower Attack",
      width = 40,       -- Width of each fire tower
      height = 150,     -- Height of the fire tower
      duration = 0.5,   -- 500 milliseconds
      timer = 0,
      towers = {},      -- Active fire towers
      damage = 1,       -- Damage multiplier
      offset = 100,     -- Distance from player
      count = 0,

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new attack when cooldown is reached
        if self.timer >= player.cooldown then
          self.timer = self.timer - player.cooldown

          -- Create left and right fire towers
          table.insert(self.towers, {
            x = player.x - self.offset,     -- Left tower
            y = player.y + 50,
            lifetime = 0,
            particles = self:createFireParticles(),
            side = "left"
          })

          table.insert(self.towers, {
            x = player.x + self.offset,     -- Right tower
            y = player.y + 50,
            lifetime = 0,
            particles = self:createFireParticles(),
            side = "right"
          })
        end

        -- Update existing towers
        for i = #self.towers, 1, -1 do
          local tower = self.towers[i]
          tower.lifetime = tower.lifetime + dt

          -- Update particle system
          tower.particles:update(dt)

          -- Update position based on player movement
          --if tower.side == "left" then
          --  tower.x = player.x - self.offset
          --else
          --  tower.x = player.x + self.offset
          --end
          --tower.y = player.y

          -- Check for enemy collisions
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]

            -- Check if enemy is within the tower's area
            local inXRange = math.abs(enemy.x - tower.x) <= self.width / 2
            local inYRange = enemy.y <= tower.y and
                enemy.y >= tower.y - (self.height * (tower.lifetime / self.duration))

            if inXRange and inYRange then
              -- Create hit effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(10)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Remove tower if duration expired
          if tower.lifetime >= self.duration then
            table.remove(self.towers, i)
          end
        end
      end,

      createFireParticles = function(self)
        local particles = love.graphics.newParticleSystem(particleImage, 200)
        particles:setParticleLifetime(0.1, 0.3)
        particles:setEmissionRate(150)
        particles:setSizeVariation(0.5)
        particles:setLinearAcceleration(-20, -200, 20, -400)
        particles:setColors(
          1, 0.5, 0.1, 1,    -- Orange
          1, 0.3, 0.1, 1,    -- Dark orange
          1, 0.1, 0.1, 0.5   -- Dark red
        )
        return particles
      end,

      draw = function(self, player)
        -- Draw active towers
        for _, tower in ipairs(self.towers) do
          -- Calculate tower height based on lifetime
          local currentHeight = self.height * (tower.lifetime / self.duration)

          -- Draw fire particles
          love.graphics.draw(tower.particles, tower.x, tower.y)

          -- Draw tower base shape
          love.graphics.setColor(1, 0.3, 0.1, 0.3)
          love.graphics.rectangle('fill',
            tower.x - self.width / 2,
            tower.y - currentHeight,
            self.width,
            currentHeight
          )

          -- Draw tower outline
          love.graphics.setColor(1, 0.5, 0.1, 0.5)
          love.graphics.rectangle('line',
            tower.x - self.width / 2,
            tower.y - currentHeight,
            self.width,
            currentHeight
          )

          -- Update particle position
          tower.particles:setPosition(tower.x, tower.y - currentHeight / 2)
          self:drawHeatDistortion(tower.x, tower.y, self.width, currentHeight)
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 80

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(1, 0.3, 0.1)
        local progress = (player.cooldown - self.timer) / player.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)
      end,

      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
        player.bpm = newBPM
      end,

      drawHeatDistortion = function(self, x, y, width, height)
        local shader = love.graphics.newShader[[
            extern number time;
            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 pixel_coords)
            {
                vec2 coords = texture_coords;
                coords.x += sin(coords.y * 10 + time) * 0.01;
                return Texel(texture, coords) * color;
            }
        ]]
        
        shader:send("time", love.timer.getTime())
        love.graphics.setShader(shader)
        -- Draw your tower here
        love.graphics.setShader()
    end
    }
  }
  return attacks
end
