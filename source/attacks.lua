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
            if distance <= self.radius + enemy.radius and
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
      width = 40,     -- Width of each fire tower
      height = 150,   -- Height of the fire tower
      duration = 0.5, -- 500 milliseconds
      timer = 0,
      towers = {},    -- Active fire towers
      damage = 1,     -- Damage multiplier
      offset = 100,   -- Distance from player
      count = 0,

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new attack when cooldown is reached
        if self.timer >= player.cooldown then
          self.timer = self.timer - player.cooldown

          -- Create left and right fire towers
          table.insert(self.towers, {
            x = player.x - self.offset, -- Left tower
            y = player.y + 50,
            lifetime = 0,
            particles = self:createFireParticles(),
            side = "left"
          })

          table.insert(self.towers, {
            x = player.x + self.offset, -- Right tower
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
          1, 0.5, 0.1, 1,  -- Orange
          1, 0.3, 0.1, 1,  -- Dark orange
          1, 0.1, 0.1, 0.5 -- Dark red
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
        local shader = love.graphics.newShader [[
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
    },
    [5] = {
      name = "Bouncing Knife Attack",
      size = 20,          -- Size of the knife
      speed = 500,        -- Speed of the knife
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      knives = {},        -- Active knives
      maxBounces = 3,     -- Default number of bounces before destroying
      damage = 1,         -- Damage multiplier
      penetration = 1,    -- Number of enemies it can hit before destroying
      knifeTypes = {
        normal = {
          color = { 0.8, 0.8, 0.8 },
          trailColor = { 1, 1, 1 }
        },
        fire = {
          color = { 1, 0.5, 0 },
          trailColor = { 1, 0.3, 0 }
        },
        ice = {
          color = { 0.5, 0.8, 1 },
          trailColor = { 0.7, 0.9, 1 }
        }
      },

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new attack when cooldown is reached
        if self.timer >= self.cooldown then
          self.timer = self.timer - self.cooldown

          -- Create new knife
          table.insert(self.knives, {
            x = player.x,
            y = player.y,
            angle = shipAngle, -- Use player's angle
            rotation = shipAngle,
            bounces = 0,
            hitEnemies = {}, -- Track hit enemies
            enemiesHit = 0,  -- Count of enemies hit
            trail = {}       -- Trail effect positions
          })

          -- Play throw sound
          -- if knifeThrowSound then knifeThrowSound:play() end
        end

        -- Update existing knives
        for i = #self.knives, 1, -1 do
          local knife = self.knives[i]

          -- Update position
          local dx = math.cos(knife.angle) * self.speed * dt
          local dy = math.sin(knife.angle) * self.speed * dt
          knife.x = knife.x + dx
          knife.y = knife.y + dy

          -- Add trail effect
          table.insert(knife.trail, {
            x = knife.x,
            y = knife.y,
            age = 0
          })

          -- Limit trail length
          if #knife.trail > 10 then
            table.remove(knife.trail, 1)
          end

          -- Age trail points
          for _, point in ipairs(knife.trail) do
            point.age = point.age + dt
          end

          -- Check screen bounds and bounce
          local bounced = false
          if knife.x < 0 then
            knife.x = 0
            knife.angle = math.pi - knife.angle
            bounced = true
          elseif knife.x > love.graphics.getWidth() then
            knife.x = love.graphics.getWidth()
            knife.angle = math.pi - knife.angle
            bounced = true
          end

          if knife.y < 0 then
            knife.y = 0
            knife.angle = -knife.angle
            bounced = true
          elseif knife.y > love.graphics.getHeight() then
            knife.y = love.graphics.getHeight()
            knife.angle = -knife.angle
            bounced = true
          end

          if bounced then
            self:createHitSpark(knife.x, knife.y)
            knife.bounces = knife.bounces + 1
            knife.rotation = knife.angle
            -- Play bounce sound
            -- if knifeBounceSound then knifeBounceSound:play() end
          end

          -- Check for enemy collisions
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - knife.x
            local dy = enemy.y - knife.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= self.size + enemy.radius and
                not knife.hitEnemies[j] and
                knife.enemiesHit < self.penetration then
              -- Mark enemy as hit
              knife.hitEnemies[j] = true
              knife.enemiesHit = knife.enemiesHit + 1

              if love.math.random() < 0.1 then -- 10% crit chance
                -- Critical hit
                knife.enemiesHit = knife.enemiesHit + 1
                self:createCriticalEffect(enemy.x, enemy.y)
                player.xp = player.xp + (self.damage * 2 * (player.xpMultiplier or 1))
              end

              -- Create hit effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(10)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()

              -- Remove knife if penetration limit reached
              if knife.enemiesHit >= self.penetration then
                table.remove(self.knives, i)
                break
              end
            end
          end

          -- Remove knife if max bounces reached
          if knife.bounces >= self.maxBounces then
            table.remove(self.knives, i)
          end
        end
      end,

      draw = function(self, player)
        -- Draw active knives
        for _, knife in ipairs(self.knives) do
          -- Draw trail
          for i, point in ipairs(knife.trail) do
            local alpha = 1 - (point.age * 2)
            if alpha > 0 then
              love.graphics.setColor(1, 1, 1, alpha * 0.5)
              love.graphics.circle('fill', point.x, point.y, 2)
            end
          end

          -- Draw knife
          love.graphics.push()
          love.graphics.translate(knife.x, knife.y)
          love.graphics.rotate(knife.rotation)

          -- Knife body
          love.graphics.setColor(0.8, 0.8, 0.8)
          love.graphics.polygon('fill',
            -self.size, -self.size / 4,
            self.size, 0,
            -self.size, self.size / 4
          )

          -- Knife handle
          love.graphics.setColor(0.6, 0.4, 0.2)
          love.graphics.rectangle('fill',
            -self.size, -self.size / 4,
            self.size / 2, self.size / 2
          )

          love.graphics.pop()
          if #knife.trail > 1 then
            love.graphics.setColor(1, 1, 1, 0.3)
            for i = 1, #knife.trail - 1 do
              love.graphics.line(
                knife.trail[i].x, knife.trail[i].y,
                knife.trail[i + 1].x, knife.trail[i + 1].y
              )
            end
          end
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 100

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(0.8, 0.8, 0.8)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw stats
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Bounces: %d", self.maxBounces),
          barX + barWidth + 10, barY)
        love.graphics.print(string.format("Penetration: %d", self.penetration),
          barX + barWidth + 10, barY + 15)
      end,
      createHitSpark = function(self, x, y)
        local spark = {
          x = x,
          y = y,
          lifetime = 0,
          maxLifetime = 0.2,
          particles = love.graphics.newParticleSystem(particleImage, 20)
        }

        spark.particles:setParticleLifetime(0.1, 0.2)
        spark.particles:setEmissionRate(100)
        spark.particles:setSizeVariation(0.5)
        spark.particles:setLinearAcceleration(-200, -200, 200, 200)
        spark.particles:setColors(1, 1, 0.5, 1, 1, 0.5, 0, 0)

        return spark
      end,
      createCriticalEffect = function(x, y, angle)
        local sparks = {}
        local sparkCount = 5

        for i = 1, sparkCount do
          local sparkAngle = angle + love.math.random(-math.pi / 4, math.pi / 4)
          table.insert(sparks, {
            x = x,
            y = y,
            dx = math.cos(sparkAngle) * 200,
            dy = math.sin(sparkAngle) * 200,
            lifetime = 0,
            maxLifetime = 0.2
          })
        end

        return sparks
      end,
      updateBPM = function(self, newBPM)
        player.cooldown = 60 / newBPM
        player.bpm = newBPM
      end,
    },
    [6] = {
      name = "Laser Beam Attack",
      length = 500,       -- Length of the laser
      width = 4,          -- Width of the laser beam
      duration = 0.3,     -- Duration of each laser burst
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      damage = 1,
      active = false,    -- Whether laser is currently firing
      activeTimer = 0,   -- Track active duration
      angle = 0,         -- Current angle of the laser
      rotationSpeed = 5, -- Rotation speed in radians per second
      autoRotate = true, -- Whether the laser auto-rotates or follows mouse/player direction

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Update laser angle
        if self.autoRotate then
          self.angle = self.angle + self.rotationSpeed * dt
        else
          self.angle = shipAngle -- Or use mouse angle
        end

        -- Start new laser burst when cooldown is reached
        if self.timer >= self.cooldown then
          self:addScreenShake(50)
          self.timer = self.timer - self.cooldown
          self.active = true
          self.activeTimer = 0

          -- Play laser sound
          -- if laserSound then laserSound:play() end
        end

        -- Update active laser
        if self.active then
          self.activeTimer = self.activeTimer + dt

          -- Calculate laser end point
          local endX = player.x + math.cos(self.angle) * self.length
          local endY = player.y + math.sin(self.angle) * self.length

          -- Check for enemy collisions along the laser line
          for i = #enemies, 1, -1 do
            local enemy = enemies[i]

            -- Check if enemy intersects with laser line
            local dx = enemy.x - player.x
            local dy = enemy.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- Calculate distance from enemy to laser line
            local enemyAngleToPlayer = math.atan2(dy, dx)
            local angleDiff = math.abs(enemyAngleToPlayer - self.angle)
            while angleDiff > math.pi do
              angleDiff = math.abs(angleDiff - 2 * math.pi)
            end

            local distanceToLine = math.sin(angleDiff) * dist

            -- If enemy is close enough to laser and within its length
            if distanceToLine < 5 + self.width / 2 and
                dist * math.cos(angleDiff) < self.length then
              -- Create destruction effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(20)

              -- Remove enemy
              table.remove(enemies, i)
              self:createLaserImpactEffect(enemy.x, enemy.y)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Deactivate laser if duration exceeded
          if self.activeTimer >= self.duration then
            self.active = false
          end
        end
      end,

      draw = function(self, player)
        if self.active then
          -- Calculate laser end point
          local endX = player.x + math.cos(self.angle) * self.length
          local endY = player.y + math.sin(self.angle) * self.length

          -- Draw laser glow (outer layer)
          love.graphics.setLineWidth(self.width + 4)
          love.graphics.setColor(1, 0, 0, 0.3)
          love.graphics.line(player.x, player.y, endX, endY)

          -- Draw laser core (inner layer)
          love.graphics.setLineWidth(self.width)
          love.graphics.setColor(1, 0.5, 0.5, 0.8)
          love.graphics.line(player.x, player.y, endX, endY)

          -- Draw laser center (brightest part)
          love.graphics.setLineWidth(self.width / 2)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.line(player.x, player.y, endX, endY)

          -- Reset line width
          love.graphics.setLineWidth(1)

          -- Draw impact point
          love.graphics.setColor(1, 1, 1, 0.8)
          love.graphics.circle('fill', endX, endY, self.width)

          -- Optional: Draw rotation indicator
          if self.autoRotate then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.arc('line', player.x, player.y, 30,
              self.angle - math.pi / 4, self.angle + math.pi / 4)
          end
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 120

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(1, 0, 0)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw laser stats
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Rotation Speed: %.1f", self.rotationSpeed),
          barX + barWidth + 10, barY)
      end,

      updateBPM = function(self, newBPM)
        self.cooldown = 60 / newBPM
      end,
      createLaserImpactEffect = function(self, x, y)
        local effect = {
          x = x,
          y = y,
          radius = 5,
          lifetime = 0,
          maxLifetime = 0.2
        }

        local particles = love.graphics.newParticleSystem(particleImage, 50)
        particles:setParticleLifetime(0.1, 0.2)
        particles:setEmissionRate(200)
        particles:setSizeVariation(0.5)
        particles:setLinearAcceleration(-200, -200, 200, 200)
        particles:setColors(1, 0.5, 0.5, 1, 1, 0, 0, 0)

        return effect, particles
      end,

      -- Optional: Add screen shake when laser is active
      addScreenShake = function(self, intensity)
        if attacks[6].active then
          love.graphics.translate(
            love.math.random(-intensity, intensity),
            love.math.random(-intensity, intensity)
          )
        end
      end
    },
    [7] = {
      name = "V-Wall Attack",
      wallLength = 100,   -- Initial length of each wall segment
      wallWidth = 4,      -- Width of the wall
      duration = 0.8,     -- How long the walls take to close
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      damage = 1,
      walls = {},             -- Active wall pairs
      closingSpeed = 300,     -- Speed at which the walls close
      startAngle = 0,         -- Start as straight line (0 degrees)
      endAngle = math.pi / 2, -- End angle for V shape (60 degrees)

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new wall attack when cooldown is reached
        if self.timer >= self.cooldown then
          self.timer = self.timer - self.cooldown

          -- Create new straight line that will morph into V shape
          local centerX = player.x
          local centerY = player.y

          table.insert(self.walls, {
            centerX = centerX, -- Store center point
            centerY = centerY,
            -- Left wall segment
            x1 = centerX - self.wallLength / 2,
            y1 = centerY,
            -- Right wall segment
            x2 = centerX + self.wallLength / 2,
            y2 = centerY,
            lifetime = 0,
            hitEnemies = {} -- Track hit enemies
          })

          -- Play wall creation sound
          -- if wallSound then wallSound:play() end
        end

        -- Update existing walls
        for i = #self.walls, 1, -1 do
          local wall = self.walls[i]
          wall.lifetime = wall.lifetime + dt

          -- Calculate morphing progress (0 to 1)
          local progress = math.min(wall.lifetime / self.duration, 1)

          -- Calculate current angles for both segments
          local leftAngle = -self.endAngle * progress
          local rightAngle = self.endAngle * progress

          -- Update wall segment positions
          -- Left segment
          wall.x1 = wall.centerX + math.cos(leftAngle) * (-self.wallLength / 2)
          wall.y1 = wall.centerY + math.sin(leftAngle) * (-self.wallLength / 2)

          -- Right segment
          wall.x2 = wall.centerX + math.cos(rightAngle) * (self.wallLength / 2)
          wall.y2 = wall.centerY + math.sin(rightAngle) * (self.wallLength / 2)

          -- Check for enemy collisions with both segments
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]

            -- Function to check distance from point to line segment
            local function distToSegment(px, py, x1, y1, x2, y2)
              local A = px - x1
              local B = py - y1
              local C = x2 - x1
              local D = y2 - y1

              local dot = A * C + B * D
              local len_sq = C * C + D * D
              local param = -1

              if len_sq ~= 0 then
                param = dot / len_sq
              end

              local xx, yy

              if param < 0 then
                xx = x1
                yy = y1
              elseif param > 1 then
                xx = x2
                yy = y2
              else
                xx = x1 + param * C
                yy = y1 + param * D
              end

              local dx = px - xx
              local dy = py - yy
              return math.sqrt(dx * dx + dy * dy)
            end

            -- Check collision with both wall segments
            local dist1 = distToSegment(enemy.x, enemy.y, wall.centerX, wall.centerY, wall.x1, wall.y1)
            local dist2 = distToSegment(enemy.x, enemy.y, wall.centerX, wall.centerY, wall.x2, wall.y2)

            -- If enemy is close enough to either segment and hasn't been hit
            if (dist1 <= 5 + self.wallWidth / 2 or
                  dist2 <= 5 + self.wallWidth / 2) and
                not wall.hitEnemies[j] then
              -- Mark enemy as hit
              wall.hitEnemies[j] = true

              -- Create hit effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(15)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Remove wall if duration exceeded
          if wall.lifetime >= self.duration then
            table.remove(self.walls, i)
          end
        end
      end,

      draw = function(self, player)
        -- Draw active walls
        for _, wall in ipairs(self.walls) do
          -- Draw wall glow
          love.graphics.setLineWidth(self.wallWidth + 4)
          love.graphics.setColor(0.8, 0.3, 0.8, 0.3)
          love.graphics.line(wall.centerX, wall.centerY, wall.x1, wall.y1)
          love.graphics.line(wall.centerX, wall.centerY, wall.x2, wall.y2)

          -- Draw wall core
          love.graphics.setLineWidth(self.wallWidth)
          love.graphics.setColor(1, 0.5, 1, 0.8)
          love.graphics.line(wall.centerX, wall.centerY, wall.x1, wall.y1)
          love.graphics.line(wall.centerX, wall.centerY, wall.x2, wall.y2)

          -- Draw wall center
          love.graphics.setLineWidth(self.wallWidth / 2)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.line(wall.centerX, wall.centerY, wall.x1, wall.y1)
          love.graphics.line(wall.centerX, wall.centerY, wall.x2, wall.y2)

          -- Reset line width
          love.graphics.setLineWidth(1)

          -- Draw energy particles along the walls
          local particleCount = 5
          for i = 0, particleCount do
            local t = i / particleCount
            -- Left segment particles
            local px1 = wall.centerX + (wall.x1 - wall.centerX) * t
            local py1 = wall.centerY + (wall.y1 - wall.centerY) * t
            -- Right segment particles
            local px2 = wall.centerX + (wall.x2 - wall.centerX) * t
            local py2 = wall.centerY + (wall.y2 - wall.centerY) * t

            love.graphics.setColor(1, 0.7, 1, 0.5 * (1 - wall.lifetime / self.duration))
            love.graphics.circle('fill', px1, py1, 2)
            love.graphics.circle('fill', px2, py2, 2)
          end

          -- Draw center point
          love.graphics.setColor(1, 1, 1, 0.8)
          love.graphics.circle('fill', wall.centerX, wall.centerY, 3)
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 140

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(1, 0.5, 1)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw wall stats
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Wall Length: %.0f", self.wallLength),
          barX + barWidth + 10, barY)
      end,

      updateBPM = function(self, newBPM)
        self.cooldown = 60 / newBPM
      end
    },
    [8] = {
      name = "Poison Cloud Attack",
      radius = 50,        -- Radius of poison cloud
      duration = 1.5,     -- Duration of poison cloud (now used as backup if cloud doesn't leave screen)
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      damage = 1,
      clouds = {},      -- Active poison clouds
      poisonMarks = {}, -- Poison marks left by dead enemies
      markDuration = 3, -- How long poison marks last
      markRadius = 20,  -- Size of poison marks
      cloudSpeed = 150, -- Speed of cloud movement

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new poison cloud when cooldown is reached
        if self.timer >= self.cooldown then
          self.timer = self.timer - self.cooldown

          -- Create new poison cloud at player position with random direction
          local angle = love.math.random() * math.pi * 2
          table.insert(self.clouds, {
            x = player.x,
            y = player.y,
            dx = math.cos(angle) * self.cloudSpeed,
            dy = math.sin(angle) * self.cloudSpeed,
            lifetime = 0,
            radius = self.radius,
            hitEnemies = {}, -- Track hit enemies
            particles = self:createPoisonParticles()
          })

          -- Play poison cloud sound
          -- if poisonCloudSound then poisonCloudSound:play() end
        end

        -- Update existing clouds
        for i = #self.clouds, 1, -1 do
          local cloud = self.clouds[i]
          cloud.lifetime = cloud.lifetime + dt

          -- Update cloud position
          cloud.x = cloud.x + cloud.dx * dt
          cloud.y = cloud.y + cloud.dy * dt

          -- Update particle system
          cloud.particles:update(dt)
          cloud.particles:setPosition(cloud.x, cloud.y)

          -- Check for enemy collisions
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - cloud.x
            local dy = enemy.y - cloud.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= cloud.radius + enemy.radius and
                not cloud.hitEnemies[j] then
              -- Mark enemy as hit
              cloud.hitEnemies[j] = true

              -- Create poison mark where enemy died
              table.insert(self.poisonMarks, {
                x = enemy.x,
                y = enemy.y,
                lifetime = 0,
                particles = self:createPoisonParticles(),
                hitEnemies = {} -- Track enemies hit by this mark
              })

              -- Create death effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(15)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Check if cloud is off screen
          local screenBuffer = self.radius * 2 -- Give some buffer space
          if cloud.x < -screenBuffer or
              cloud.x > love.graphics.getWidth() + screenBuffer or
              cloud.y < -screenBuffer or
              cloud.y > love.graphics.getHeight() + screenBuffer then
            table.remove(self.clouds, i)
            -- Backup duration check if cloud somehow gets stuck
          elseif cloud.lifetime >= self.duration then
            table.remove(self.clouds, i)
          end
        end

        -- Update poison marks (same as before)
        for i = #self.poisonMarks, 1, -1 do
          local mark = self.poisonMarks[i]
          mark.lifetime = mark.lifetime + dt

          -- Update particle system
          mark.particles:update(dt)
          mark.particles:setPosition(mark.x, mark.y)

          -- Check for enemy collisions with mark
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - mark.x
            local dy = enemy.y - mark.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= self.markRadius + enemy.radius and
                not mark.hitEnemies[j] then
              -- Mark enemy as hit
              mark.hitEnemies[j] = true

              -- Create death effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(15)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()

              -- Remove the current mark after it kills an enemy
              table.remove(self.poisonMarks, i)
              break
            end
          end
        end
      end,

      createPoisonParticles = function(self)
        local particles = love.graphics.newParticleSystem(particleImage, 100)
        particles:setParticleLifetime(0.5, 1)
        particles:setEmissionRate(50)
        particles:setSizeVariation(0.5)
        particles:setLinearAcceleration(-20, -20, 20, 20)
        particles:setColors(
          0.2, 0.8, 0.2, 0.7, -- Green
          0.1, 0.5, 0.1, 0    -- Dark green fade out
        )
        -- Add spread in the movement direction
        particles:setSpread(math.pi / 4)
        return particles
      end,

      draw = function(self, player)
        -- Draw poison marks
        for _, mark in ipairs(self.poisonMarks) do
          -- Draw mark base
          local alpha = math.min(1, (self.markDuration - mark.lifetime) / self.markDuration)
          love.graphics.setColor(0.2, 0.6, 0.2, 0.3 * alpha)
          love.graphics.circle('fill', mark.x, mark.y, self.markRadius)

          -- Draw mark outline
          love.graphics.setColor(0.3, 0.8, 0.3, 0.5 * alpha)
          love.graphics.circle('line', mark.x, mark.y, self.markRadius)

          -- Draw particles
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(mark.particles)
        end

        -- Draw poison clouds
        for _, cloud in ipairs(self.clouds) do
          -- Draw cloud base
          local alpha = math.min(1, (self.duration - cloud.lifetime) / self.duration)
          love.graphics.setColor(0.2, 0.8, 0.2, 0.2 * alpha)
          love.graphics.circle('fill', cloud.x, cloud.y, cloud.radius)

          -- Draw cloud outline
          love.graphics.setColor(0.3, 1, 0.3, 0.4 * alpha)
          love.graphics.circle('line', cloud.x, cloud.y, cloud.radius)

          -- Draw particles
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(cloud.particles)
        end

        if #self.poisonMarks > 1 then
          love.graphics.setColor(0.2, 0.8, 0.2, 0.2)
          for i = 1, #self.poisonMarks - 1 do
            local m1 = self.poisonMarks[i]
            local m2 = self.poisonMarks[i + 1]
            love.graphics.line(m1.x, m1.y, m2.x, m2.y)
          end
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 160

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(0.2, 0.8, 0.2)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw stats
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Poison Radius: %.0f", self.radius),
          barX + barWidth + 10, barY)
        love.graphics.print(string.format("Active Marks: %d", #self.poisonMarks),
          barX + barWidth + 10, barY + 15)
      end,

      updateBPM = function(self, newBPM)
        self.cooldown = 60 / newBPM
      end
    },
    [9] = {
      name = "Blood Arc Attack",
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      damage = 1,
      arcs = {},             -- Active blood arcs
      arcSize = 20,          -- Size of the blood arc
      throwSpeed = 100,      -- Initial throw speed (reduced to 100)
      gravity = 800,         -- Gravity effect
      arcHeight = 100,       -- How high the arc goes (reduced to 100)
      splatterCount = 3,     -- How many blood drops split from main arc
      count = 2,             -- Number of arcs to throw at once (new property)
      spreadAngle = math.pi / 6, -- Angle between multiple arcs

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new arc when cooldown is reached
        if self.timer >= self.cooldown then
          self.timer = self.timer - self.cooldown

          -- Calculate initial velocity based on desired height
          local initialVelocityY = -math.sqrt(2 * self.gravity * self.arcHeight)

          -- Calculate base angle for spreading multiple arcs
          --local baseAngle = -self.spreadAngle * (self.count - 1) / 2

          -- Create multiple arcs based on count
          for i = 1, self.count do
            -- Calculate spread angle for this arc
            local patternOffset = (love.timer.getTime() % 2) * math.pi / 4
            local baseAngle = (i - 1) * (2 * math.pi / self.count) + patternOffset
            local spreadAngle = baseAngle + (i - 1) * self.spreadAngle

            -- Calculate directional velocities based on spread
            local throwSpeedX = self.throwSpeed * math.cos(spreadAngle)
            local throwSpeedY = self.throwSpeed * math.sin(spreadAngle)

            -- Create new blood arc
            table.insert(self.arcs, {
              x = player.x,
              y = player.y,
              dx = throwSpeedX,                          -- Horizontal speed with spread
              dy = initialVelocityY + throwSpeedY,       -- Vertical speed with spread
              size = self.arcSize,
              trail = {},
              splatters = {},            -- Child blood splatters
              splatterTimer = 0.1,       -- Time between splatter releases
              splatterCount = 0,         -- How many splatters released
              hitEnemies = {}
            })
          end
        end

        -- Update existing arcs
        for i = #self.arcs, 1, -1 do
          local arc = self.arcs[i]

          -- Update position
          arc.x = arc.x + arc.dx * dt
          arc.y = arc.y + arc.dy * dt

          -- Apply gravity
          arc.dy = arc.dy + self.gravity * dt

          -- Update splatter timer
          arc.splatterTimer = arc.splatterTimer - dt

          -- Release blood splatters periodically
          if arc.splatterTimer <= 0 and arc.splatterCount < self.splatterCount then
            arc.splatterTimer = 0.1
            arc.splatterCount = arc.splatterCount + 1

            -- Create new splatter
            table.insert(arc.splatters, {
              x = arc.x,
              y = arc.y,
              dx = arc.dx * 0.5 + love.math.random(-100, 100),
              dy = arc.dy * 0.5 + love.math.random(-100, 0),
              size = arc.size * 0.5,
              trail = {},
              hitEnemies = {}
            })
          end

          -- Add trail effect
          table.insert(arc.trail, {
            x = arc.x,
            y = arc.y,
            age = 0
          })

          -- Limit trail length
          if #arc.trail > 10 then
            table.remove(arc.trail, 1)
          end

          -- Age trail points
          for _, point in ipairs(arc.trail) do
            point.age = point.age + dt
          end

          -- Update splatters
          for j = #arc.splatters, 1, -1 do
            local splatter = arc.splatters[j]

            -- Update splatter position
            splatter.x = splatter.x + splatter.dx * dt
            splatter.y = splatter.y + splatter.dy * dt

            -- Apply gravity to splatter
            splatter.dy = splatter.dy + self.gravity * dt

            -- Add splatter trail
            table.insert(splatter.trail, {
              x = splatter.x,
              y = splatter.y,
              age = 0
            })

            -- Limit splatter trail length
            if #splatter.trail > 5 then
              table.remove(splatter.trail, 1)
            end

            -- Age splatter trail points
            for _, point in ipairs(splatter.trail) do
              point.age = point.age + dt
            end

            -- Check splatter collisions with enemies
            for k = #enemies, 1, -1 do
              local enemy = enemies[k]
              local dx = enemy.x - splatter.x
              local dy = enemy.y - splatter.y
              local distance = math.sqrt(dx * dx + dy * dy)

              if distance <= splatter.size + enemy.radius and
                  not splatter.hitEnemies[k] then
                -- Mark enemy as hit
                splatter.hitEnemies[k] = true

                -- Create hit effect
                particles:setPosition(enemy.x, enemy.y)
                particles:emit(10)

                -- Remove enemy
                table.remove(enemies, k)

                -- Add XP
                player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
                checkLevelUp()
              end
            end

            -- Remove splatter if off screen
            if splatter.y > love.graphics.getHeight() then
              table.remove(arc.splatters, j)
            end
          end

          -- Check main arc collisions with enemies
          for j = #enemies, 1, -1 do
            local enemy = enemies[j]
            local dx = enemy.x - arc.x
            local dy = enemy.y - arc.y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= arc.size + enemy.radius and
                not arc.hitEnemies[j] then
              -- Mark enemy as hit
              arc.hitEnemies[j] = true

              -- Create hit effect
              particles:setPosition(enemy.x, enemy.y)
              particles:emit(20)

              -- Remove enemy
              table.remove(enemies, j)

              -- Add XP
              player.xp = player.xp + (self.damage * (player.xpMultiplier or 1))
              checkLevelUp()
            end
          end

          -- Remove arc if off screen
          if arc.y > love.graphics.getHeight() or
              arc.x > love.graphics.getWidth() then
            table.remove(self.arcs, i)
          end
        end
      end,

      draw = function(self)
        for _, arc in ipairs(self.arcs) do
          -- Draw splatters
          for _, splatter in ipairs(arc.splatters) do
            -- Draw splatter trail
            for i, point in ipairs(splatter.trail) do
              local alpha = 1 - (point.age * 2)
              if alpha > 0 then
                love.graphics.setColor(0.8, 0, 0, alpha * 0.3)
                love.graphics.circle('fill', point.x, point.y, splatter.size * 0.5)
              end
            end

            -- Draw splatter
            love.graphics.setColor(0.8, 0, 0, 1)
            love.graphics.circle('fill', splatter.x, splatter.y, splatter.size)
            love.graphics.setColor(1, 0, 0, 1)
            love.graphics.circle('line', splatter.x, splatter.y, splatter.size)
          end

          -- Draw main arc trail
          for i, point in ipairs(arc.trail) do
            local alpha = 1 - (point.age * 2)
            if alpha > 0 then
              love.graphics.setColor(0.8, 0, 0, alpha * 0.5)
              love.graphics.circle('fill', point.x, point.y, arc.size * 0.7)
            end
          end

          -- Draw main arc
          love.graphics.setColor(0.8, 0, 0, 1)
          love.graphics.circle('fill', arc.x, arc.y, arc.size)
          love.graphics.setColor(1, 0, 0, 1)
          love.graphics.circle('line', arc.x, arc.y, arc.size)
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 200

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(0.8, 0, 0)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)
      end,

      updateBPM = function(self, newBPM)
        self.cooldown = 60 / newBPM
      end
    },
    [10] = {
      name = "Flame Thrower Attack",
      cooldown = 60 / 60, -- 60/bpm
      timer = 0,
      damage = 1,
      isActive = false, -- Whether flame thrower is currently firing
      duration = 0.5,   -- How long flame thrower stays active
      durationTimer = 0, -- Timer for active duration
      baseRange = 150,  -- Initial range of flame thrower
      maxRange = 400,   -- Maximum possible range
      currentRange = 150, -- Current range (changes with upgrades)
      width = 40,       -- Width of flame cone
      particles = {},   -- Active flame particles
      hitEnemies = {},  -- Tracked per activation
      angle = 0,
      speed = 0,
      rotationSpeed = 5,

      update = function(self, dt, player, enemies)
        -- Update attack timer
        self.timer = self.timer + dt

        -- Start new flame burst when cooldown is reached
        if self.timer >= self.cooldown and not self.isActive then
          self.timer = self.timer - self.cooldown
          self.isActive = true
          self.durationTimer = self.duration
          self.hitEnemies = {}   -- Reset hit enemies for new activation

          -- Play flame sound
          -- if flameSound then flameSound:play() end
        end

        -- Update duration timer if active
        if self.isActive then
          self.durationTimer = self.durationTimer - dt

          if self.durationTimer <= 0 then
            self.isActive = false
          end

          -- Create new flame particles
          for i = 1, 5 do   -- Create multiple particles per frame
            self.angle = shipAngle
            local speed = love.math.random(200, 400)
            local lifetime = love.math.random(0.2, 0.4)
            local startDistance = 30     -- Start flames a bit away from player

            table.insert(self.particles, {
              x = player.x + math.cos(self.angle) * startDistance,
              y = player.y + math.sin(self.angle) * startDistance,
              dx = math.cos(self.angle) * speed,
              dy = math.sin(self.angle) * speed,
              size = love.math.random(10, 20),
              lifetime = lifetime,
              maxLifetime = lifetime,
              color = {
                r = love.math.random(0.8, 1),
                g = love.math.random(0.2, 0.4),
                b = 0
              }
            })
          end
        end

        -- Update existing particles
        for i = #self.particles, 1, -1 do
          local particle = self.particles[i]

          -- Update position
          particle.x = particle.x + particle.dx * dt
          particle.y = particle.y + particle.dy * dt

          -- Update lifetime
          particle.lifetime = particle.lifetime - dt

          -- Check distance from player
          local dx = particle.x - player.x
          local dy = particle.y - player.y
          local distance = math.sqrt(dx * dx + dy * dy)

          -- Remove if lifetime expired or too far
          if particle.lifetime <= 0 or distance > self.currentRange then
            table.remove(self.particles, i)
          else
            -- Check for enemy collisions
            for j = #enemies, 1, -1 do
              local enemy = enemies[j]
              local edx = enemy.x - particle.x
              local edy = enemy.y - particle.y
              local eDistance = math.sqrt(edx * edx + edy * edy)

              if eDistance <= particle.size + enemy.radius and
                  not self.hitEnemies[j] then
                -- Mark enemy as hit
                self.hitEnemies[j] = true

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
          end
        end
      end,

      draw = function(self, player)
        -- Draw flame particles
        for _, particle in ipairs(self.particles) do
          -- Calculate alpha based on lifetime
          local alpha = particle.lifetime / particle.maxLifetime

          -- Draw particle
          love.graphics.setColor(
            particle.color.r,
            particle.color.g,
            particle.color.b,
            alpha
          )
          love.graphics.circle('fill', particle.x, particle.y, particle.size)
        end

        -- Draw range indicator when active
        if self.isActive then
          love.graphics.setColor(1, 0.5, 0, 0.2)
          local segments = 32
          local angleStep = math.pi / 4 / segments
          for i = 0, segments do
            local angle1 = self.angle - math.pi / 8 + angleStep * i
            local angle2 = self.angle - math.pi / 8 + angleStep * (i + 1)
            love.graphics.polygon('fill',
              player.x, player.y,
              player.x + math.cos(angle1) * self.currentRange,
              player.y + math.sin(angle1) * self.currentRange,
              player.x + math.cos(angle2) * self.currentRange,
              player.y + math.sin(angle2) * self.currentRange
            )
          end
        end

        -- Draw duration bar when active
        if self.isActive then
          local barWidth = 100
          local barHeight = 10
          local barX = love.graphics.getWidth() - barWidth - 10
          local barY = 10

          -- Background
          love.graphics.setColor(0.2, 0.2, 0.2)
          love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

          -- Progress
          love.graphics.setColor(1, 0.5, 0)
          local progress = self.durationTimer / self.duration
          love.graphics.rectangle('fill', barX, barY, barWidth * progress, barHeight)
        end

        -- Draw cooldown bar
        love.graphics.setColor(1, 1, 1)
        local barWidth = 100
        local barHeight = 10
        local barX = 10
        local barY = love.graphics.getHeight() - 220

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle('fill', barX, barY, barWidth, barHeight)

        -- Progress
        love.graphics.setColor(1, 0.5, 0)
        local progress = (self.cooldown - self.timer) / self.cooldown
        love.graphics.rectangle('fill', barX, barY, barWidth * (1 - progress), barHeight)

        -- Draw stats
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Range: %.0f", self.currentRange),
          barX + barWidth + 10, barY)
        love.graphics.print(string.format("Duration: %.1fs", self.duration),
          barX + barWidth + 10, barY + 15)
      end,

      updateBPM = function(self, newBPM)
        self.cooldown = 60 / newBPM
      end
    }
  }
  return attacks
end
