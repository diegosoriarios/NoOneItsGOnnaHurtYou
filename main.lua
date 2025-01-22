require("source/audio")

function love.load()
  --love.window.setFullscreen(true, "desktop")
  screen_width = love.graphics.getWidth()
  screen_height = love.graphics.getHeight()

  shipAngle = 0
  speed = 5

  enemies = {}

  player = {
    x = screen_width / 2 + math.cos(0) * 100,
    y = screen_height / 2 + math.sin(0) * 100,
    r = 15,
    distance = 100,
  }

  spawnTime = 0
	spawnTimeLimit = 2

  soundTime = 0
  bpm = 60

  kick = love.audio.newSource("sounds/kick.mp3", "static")
  hi_hat = love.audio.newSource("sounds/hi-hat.mp3", "static")
  currentSound = kick
  loop = 0
end

function love.update(dt)
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
  --handleSound(dt)
end

function love.draw()
  local shipCircleDistance = 100

  love.graphics.setColor(0, 0, 1)
  --love.graphics.circle('line', screen_width / 2, screen_height / 2, shipCircleDistance)

  love.graphics.setColor(0, 1, 1)
  love.graphics.circle(
      'fill',
      screen_width / 2 + math.cos(shipAngle) * shipCircleDistance,
      screen_height / 2 + math.sin(shipAngle) * shipCircleDistance,
      15
  )

  for enemyIndex, enemy in ipairs(enemies) do
    love.graphics.setColor(0, 1, 0)
    love.graphics.circle('fill', enemy.x, enemy.y, 5)
  end

  -- Temporary
  love.graphics.setColor(1, 1, 1)
  love.graphics.print('shipAngle: '..shipAngle)
  love.graphics.print('spawnTimer: '..spawnTime, 0, 50)
end

function spawn(dt)
  spawnTime = spawnTime + dt
	if spawnTime >= spawnTimeLimit then
		table.insert(enemies, {
      x = love.math.random(screen_width),
      y = love.math.random(screen_height),
      speed = 100
    })
		spawnTime = 0 --optional if you want it to happen repeatedly
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
      enemy.x = 200
      enemy.y = 200
    end
  end
end

function checkCircularCollision(player, enemy)
	local dx, dy, sr = enemy.x - player.x, enemy.y - player.y, 0 + player.r
	return dx*dx + dy*dy < sr*sr
end