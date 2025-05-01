require("source.audio")
require("source.attacks")
require("source.upgrades")

local states = require 'source.states'

local game = states.new('game')

function game:init()
  --love.window.setFullscreen(true, "desktop")
  screen_width = love.graphics.getWidth()
  screen_height = love.graphics.getHeight()

  shipAngle = 0
  speed = 5

  enemies = {}
  attacks = generateAttacks()
  availableUpgrades = generateUpgrades()

  shakeAmount = 0

  currentUpgradeChoices = {}
  selectedUpgrade = 1

  player = {
    x = screen_width / 2 + math.cos(0) * 100,
    y = screen_height / 2 + math.sin(0) * 100,
    r = 15,
    distance = 100,
    xp = 0,
    level = 1,
    xpToNext = 5,
    bpm = 60,
    hp = 1,
  }
  player.cooldown = 60 / player.bpm
  player.attacks = {
    attacks[0]
  }

  spawnTime = 0
	spawnTimeLimit = 2

  soundTime = 0

  kick = love.audio.newSource("sounds/kick.mp3", "static")
  hi_hat = love.audio.newSource("sounds/hi-hat.mp3", "static")
  currentSound = kick
  loop = 0
  
  attackTimer = 0
  attackDuration = 0.5
  isAttacking = false
  attackRadius = 50
  
  attackInterval = 60 / player.bpm

  particleImage = love.graphics.newImage("graphics/particle.png")
  particles = love.graphics.newParticleSystem(particleImage, 100)
  particles:setParticleLifetime(0.2, 0.4)
  particles:setLinearAcceleration(-50, -50, 50, 50)
  particles:setColors(1, 1, 1, 1, 1, 1, 1, 0)
end

function game:update(dt)
  if showUpgradeMenu then return end

  if love.keyboard.isDown('right') then
    shipAngle = shipAngle + speed * dt
    player.x = screen_width / 2 + math.cos(shipAngle) * player.distance
    player.y = screen_height / 2 + math.sin(shipAngle) * player.distance
  end

  if love.keyboard.isDown('left') then
    shipAngle = shipAngle - speed * dt
    player.x = screen_width / 2 + math.cos(shipAngle) * player.distance
    player.y = screen_height / 2 + math.sin(shipAngle) * player.distance
  end

  handleEnemyMove(dt)
  spawn(dt)
  handleAttack(dt)
  --handleSound(dt)
end

function game:keypressed(key)
  if showUpgradeMenu then
      if key == "up" then
          selectedUpgrade = selectedUpgrade - 1
          if selectedUpgrade < 1 then 
              selectedUpgrade = #currentUpgradeChoices 
          end
      elseif key == "down" then
          selectedUpgrade = selectedUpgrade + 1
          if selectedUpgrade > #currentUpgradeChoices then 
              selectedUpgrade = 1 
          end
      elseif key == "return" or key == "space" then
          currentUpgradeChoices[selectedUpgrade].apply()
          showUpgradeMenu = false
      end
  end
end

function game:draw()
  local shipCircleDistance = 100

  love.graphics.setColor(0, 0, 1)
  --love.graphics.circle('line', screen_width / 2, screen_height / 2, shipCircleDistance)

  love.graphics.setColor(0, 1, 1)
  love.graphics.circle(
      'fill',
      screen_width / 2 + math.cos(shipAngle) * shipCircleDistance,
      screen_height / 2 + math.sin(shipAngle) * shipCircleDistance,
      player.r
  )

  for enemyIndex, enemy in ipairs(enemies) do
    love.graphics.setColor(0, 1, 0)
    love.graphics.circle('fill', enemy.x, enemy.y, 5)
  end

  for _, attack in ipairs(player.attacks) do
        attack:draw(player)
    end

  -- Temporary
  love.graphics.setColor(1, 1, 1)
  love.graphics.print('shipAngle: '..shipAngle)
  love.graphics.print('spawnTimer: '..spawnTime, 0, 50)
  love.graphics.print('fps: '..love.timer.getFPS(), 0, 100)

  love.graphics.print('XP: '..player.xp..' / '..player.xpToNext, 0, 150)
  love.graphics.print('Level: '..player.level, 0, 170)

  drawUpgradeMenu()
end

function handleAttack(dt)
  for _, attack in ipairs(player.attacks) do
        attack:update(dt, player, enemies)
    end
end

function spawn(dt)
  spawnTime = spawnTime + dt
  if spawnTime >= spawnTimeLimit then
    local perimeter = 2 * (screen_width + screen_height)

    local point = love.math.random(perimeter)
    local x, y
    
    if point < screen_width then
      x = point
      y = -20
    elseif point < (screen_width + screen_height) then
      x = screen_width + 20
      y = point - screen_width
    elseif point < (2 * screen_width + screen_height) then
      x = point - (screen_width + screen_height)
      y = screen_height + 20
    else
      x = -20
      y = point - (2 * screen_width + screen_height)
    end
    
    table.insert(enemies, {
      x = x,
      y = y,
      speed = 100,
      radius = 5,
    })
    spawnTime = 0
  end
end

function handleEnemyMove(dt)
  for enemyIndex, enemy in ipairs(enemies) do
    dx = screen_width / 2 - enemy.x
    dy = screen_height / 2 - enemy.y
    local distance = math.sqrt(dx*dx+dy*dy)
    enemy.x = enemy.x + (dx / distance * enemy.speed * dt)
    enemy.y = enemy.y + (dy / distance * enemy.speed * dt)

    if checkCircularCollision(player, enemy) then
      player.xp = player.xp + 1
      table.remove(enemies, enemyIndex)

      if distance <= attackRadius then
        particles:setPosition(enemy.x, enemy.y)
        particles:emit(10)
        table.remove(enemies, i)
      end

      checkLevelUp()
    end

    if checkCircularCollision({x=0, y=0, r=0}, enemy) then
      player.hp = player.hp - 1
      if player.hp == 0 then
        states.switch('gameover')
      end
    end
  end
end

function drawUpgradeMenu()
  if not showUpgradeMenu then return end
  
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.rectangle('fill', 0, 0, screen_width, screen_height)
  
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("LEVEL UP!", screen_width/2 - 50, screen_height/3, 0, 2, 2)
  
  for i, upgrade in ipairs(currentUpgradeChoices) do
      local x = screen_width/2 - 100
      local y = screen_height/2 + (i-1) * 60
      
      if i == selectedUpgrade then
          love.graphics.setColor(1, 1, 0, 0.3)
          love.graphics.rectangle('fill', x - 10, y - 5, 220, 50)
      end
      
      love.graphics.setColor(1, 1, 1)
      love.graphics.print(upgrade.name, x, y)
      love.graphics.setColor(0.7, 0.7, 0.7)
      love.graphics.print(upgrade.description, x, y + 20, 0, 0.8, 0.8)
  end
  
  love.graphics.setColor(0.7, 0.7, 0.7)
  love.graphics.print("Use UP/DOWN to select and ENTER to confirm", 
      screen_width/2 - 150, screen_height * 0.8)
end

function checkLevelUp()
  if player.xp >= player.xpToNext then
      player.level = player.level + 1
      player.xp = player.xp - player.xpToNext
      player.xpToNext = math.floor(player.xpToNext * 1.5)
      
      currentUpgradeChoices = getRandomUpgrades(3)
      selectedUpgrade = 1
      showUpgradeMenu = true
  end
end

function checkCircularCollision(player, enemy)
	local dx, dy, sr = enemy.x - player.x, enemy.y - player.y, 0 + player.r
	return dx*dx + dy*dy < sr*sr
end