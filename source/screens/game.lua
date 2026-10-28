require("source.audio")
require("source.attacks")
require("source.upgrades")
local roster = require("source.roster")

local states = require 'source.states'
local MIDI = require "plugins.midi_engine"

local game = states.new('game')
music = nil
currentSongPath = "songs/garota_do_cemiterio.mid"

-- Unlock progression helpers. Roster entry k pairs with song layer k-1
-- (entry 1 = drums pairs with the drum track itself). Every unlock brings
-- exactly one instrument: its attack, its song layer (if the song has one)
-- and, for the drums entry, the drum track.
function nextLockedRosterEntry()
  for i = 1, #roster.ENTRIES do
    if not music.unlockedRoster[i] then
      return i, roster.ENTRIES[i]
    end
  end
end

function unlockRosterEntry(entryIndex)
  local entry = roster.ENTRIES[entryIndex]
  if not entry or music.unlockedRoster[entryIndex] then return nil end
  music.unlockedRoster[entryIndex] = true

  local attackInstance = attacks[entry.attack]
  if attackInstance then
    attackInstance.nextBeat = nil
    local s = roster.resolveAttackSound(entry.attack, currentSongPath, music.synth)
    if s then attackInstance.sound = s end
    applyPlayerStatsToAttack(attackInstance)
    table.insert(player.attacks, attackInstance)
  end

  -- the drums entry also brings the drum track itself
  if entryIndex == 1 and music.drumTrackIndex and music.drumsMuted then
    music.setTrackMuted(music.drumTrackIndex, false)
    music.drumsMuted = false
  end

  local layer = unlockLayerByIndex(entryIndex - 1)
  return entry, layer
end

function unlockLayerByIndex(layerIndex)
  local layer = music.trackLayers[layerIndex]
  if not layer or layer.unlocked then return nil end
  layer.unlocked = true
  music.setTrackMuted(layer.track, false)
  if layer.instrument then
    music.setTrackInstrument(layer.track, layer.instrument)
  end
  music.sfx(1, 72, 120, 0.6)
  return layer
end

function unlockNextRosterEntry()
  local entryIndex, entry = nextLockedRosterEntry()
  if not entry then return nil end
  return unlockRosterEntry(entryIndex)
end

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

  --AUDIO LOAD
  local data = MIDI.Parser.parse(currentSongPath)
  assert(data, "midi_engine: could not parse '" .. currentSongPath .. "'")
  music = MIDI.Player.new(data)

  -- Load every registered instrument/drum sample (missing files skip quietly)
  roster.loadInstruments(music.synth)

  -- Song convention: the drum track backs the Drummer; every other character
  -- starts solo and the drums join at the first Add Instrument. Melodic
  -- tracks are layers that start muted; layer k pairs with roster entry k+1.
  -- The layer's instrument comes from its track name (set it in your DAW) or
  -- from its roster pairing.
  music.trackLayers = {}
  local drumTrackIndex = nil
  for trackIndex, track in ipairs(data.tracks) do
    local hasNotes, hasDrums = false, false
    for _, e in ipairs(track) do
      if e.type == "noteon" then
        hasNotes = true
        if e.channel == 9 then hasDrums = true end
      end
    end
    if hasDrums and not drumTrackIndex then
      drumTrackIndex = trackIndex
    end
    if hasNotes and not hasDrums then
      local layerIndex = #music.trackLayers + 1
      local instrument = roster.instrumentIdForTrackName(data.trackNames[trackIndex])
      if not instrument then
        instrument = roster.entryMelodicId(layerIndex + 1)
      end
      table.insert(music.trackLayers, {
        track = trackIndex,
        name = data.trackNames[trackIndex] or ("Layer " .. layerIndex),
        instrument = instrument,
        unlocked = false,
      })
      music.setTrackMuted(trackIndex, true)
    end
  end
  music.delayLevel = 0
  music.unlockedRoster = {}
  music.drumTrackIndex = drumTrackIndex

  -- Song gating: map each roster entry to the beat slots where the song
  -- actually plays its instrument. Gated attacks skip slots without hits.
  local beatTimes = music.getBeatTimes()
  local window = math.max(0.04, ((beatTimes[2] or beatTimes[1]) - (beatTimes[1] or 0)) / 8)
  for entryIndex, entry in ipairs(roster.ENTRIES) do
    local attackInstance = attacks[entry.attack]
    if attackInstance then
      local noteTimes
      local layer = music.trackLayers[entryIndex - 1]
      if layer then
        noteTimes = roster.collectNoteTimes(data.tracks[layer.track])
      elseif entry.sound and entry.sound.drum and drumTrackIndex then
        -- entry 1 (the drum kit) gates on the whole groove; other kit
        -- entries gate on their specific piece
        local noteFilter
        if entryIndex ~= 1 then
          noteFilter = entry.sound.note
        end
        noteTimes = roster.collectNoteTimes(data.tracks[drumTrackIndex], noteFilter)
      end
      attackInstance.hitBeats = roster.buildHitBeats(beatTimes, noteTimes, window)
    end
  end

  -- The selected character's starter instrument joins drums from beat one.
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
    speedMul = 1,
    areaMul = 1,
    damageMul = 1,
    quantityBonus = 0,
  }
  player.attacks = {}

  -- Character starter: unlock that roster entry. The Drummer (starter 1)
  -- plays the drum track; every other character starts solo -- the drums are
  -- their own "Add Instrument" unlock later. Each starter brings its own
  -- paired song layer (entry k pairs with layer k-1) when the song has it.
  local starter = 1
  local character = states.global.selectedCharacter
  if character then
    if character.starter then starter = character.starter end
    if character.speed then speed = character.speed end
  end
  unlockRosterEntry(starter)
  music.drumsMuted = (starter ~= 1) and (music.drumTrackIndex ~= nil)
  if music.drumsMuted then
    music.setTrackMuted(music.drumTrackIndex, true)
  end

  music.play()
  player.spriteSheet = love.graphics.newImage("graphics/sprites/Character.png")
  player.animation = {
      frameWidth = 460,     -- Width of each frame
      frameHeight = 460,    -- Height of each frame
      framesPerRow = 6,    -- Number of frames per row in sprite sheet
      totalFrames = 6,     -- Total number of frames
      currentFrame = 1,    -- Current frame index
      frameTime = 0.25,     -- Time per frame (seconds)
      timer = 0,           -- Animation timer
      isPlaying = true     -- Whether animation is playing
  }
  player.frames = {}
  for i = 0, player.animation.totalFrames - 1 do
      local x = (i % player.animation.framesPerRow) * player.animation.frameWidth
      local y = math.floor(i / player.animation.framesPerRow) * player.animation.frameHeight
      
      player.frames[i + 1] = love.graphics.newQuad(
          x, y,
          player.animation.frameWidth,
          player.animation.frameHeight,
          player.spriteSheet:getDimensions()
      )
  end

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
  music.update(dt)

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
  updatePlayerAnimation(dt)
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
  

  love.graphics.draw(
        player.spriteSheet,
        player.frames[player.animation.currentFrame],
        player.x,
        player.y,
        player.angle,
        .2, .2, -- scale
        player.animation.frameWidth / 2,  -- origin x (center)
        player.animation.frameHeight / 2  -- origin y (center)
    )

  for enemyIndex, enemy in ipairs(enemies) do
    love.graphics.setColor(0, 1, 0)
    love.graphics.circle('fill', enemy.x, enemy.y, 5)
  end

  for _, attack in ipairs(player.attacks) do
        attack:draw(player)
    end

  -- Debug HUD (set DEBUG = true during development)
  local DEBUG = false
  if DEBUG then
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('shipAngle: '..shipAngle)
    love.graphics.print('spawnTimer: '..spawnTime, 0, 50)
    love.graphics.print('fps: '..love.timer.getFPS(), 0, 100)
    love.graphics.print('XP: '..player.xp..' / '..player.xpToNext, 0, 150)
    love.graphics.print('Level: '..player.level, 0, 170)
  end

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
      local description = upgrade.description
      if type(description) == "function" then description = description() end
      love.graphics.print(description, x, y + 20, 0, 0.8, 0.8)
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

function updatePlayerAnimation(dt)
    if player.animation.isPlaying then
        player.animation.timer = player.animation.timer + dt
        
        if player.animation.timer >= player.animation.frameTime then
            player.animation.timer = player.animation.timer - player.animation.frameTime
            player.animation.currentFrame = player.animation.currentFrame + 1
            
            if player.animation.currentFrame > player.animation.totalFrames then
                player.animation.currentFrame = 1
            end
        end
    end
end