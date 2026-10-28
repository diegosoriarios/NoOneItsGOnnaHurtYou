-- Upgrades. Two families:
--   * "Add <Instrument>" — one per roster entry, free choice, level-gated.
--   * Generic stat upgrades that apply to EVERY instrument (current arsenal
--     and anything unlocked later, via player-level multipliers).
local roster = require("source.roster")

-- Music unlocks are paced: the Nth attack in the arsenal requires level 3N
-- (1st at level 3, 2nd at level 6, ...).
local function levelGateOpen()
  return player ~= nil and player.level >= 3 * #player.attacks
end

-- Stat fields shared by all attacks. A generic upgrade touches every field
-- present on the attack (attacks only define the ones they use).
local STAT_FIELDS = {
  speed = { "speed", "bulletSpeed", "throwSpeed", "rotationSpeed", "closingSpeed", "cloudSpeed" },
  area = { "radius", "size", "width", "height", "length", "wallLength", "arcSize",
           "maxDistance", "markRadius", "arcHeight", "currentRange" },
  damage = { "damage" },
}

local MULT_STEP = 1.1

local function scaleFields(attack, fields, factor)
  for _, field in ipairs(fields) do
    local value = attack[field]
    if type(value) == "number" then
      attack[field] = value * factor
    end
  end
end

-- Apply the player's current multipliers to a freshly unlocked attack (its
-- stats are still base values: each attack instance is unlocked only once).
function applyPlayerStatsToAttack(attack)
  scaleFields(attack, STAT_FIELDS.speed, player.speedMul or 1)
  scaleFields(attack, STAT_FIELDS.area, player.areaMul or 1)
  scaleFields(attack, STAT_FIELDS.damage, player.damageMul or 1)
  if type(attack.count) == "number" then
    attack.count = attack.count + (player.quantityBonus or 0)
  end
end

local function scaleOwnedAttacks(fields, factor)
  for _, attack in ipairs(player.attacks) do
    scaleFields(attack, fields, factor)
  end
end

local function addToOwnedCount(bonus)
  for _, attack in ipairs(player.attacks) do
    if type(attack.count) == "number" then
      attack.count = attack.count + bonus
    end
  end
end

local function addInstrumentUpgrade(entryIndex, entry)
  return {
    name = "Add " .. entry.instrument,
    musicUnlock = true,
    description = function()
      if entryIndex == 1 then
        return "Circle attack + the song's drum track"
      end
      local layer = music and music.trackLayers and music.trackLayers[entryIndex - 1]
      if layer then
        return "New attack + the song's " .. layer.name .. " layer"
      end
      return "New attack: " .. entry.instrument
    end,
    canOffer = function()
      return music ~= nil and not music.unlockedRoster[entryIndex] and levelGateOpen()
    end,
    apply = function()
      unlockRosterEntry(entryIndex)
    end,
  }
end

function generateUpgrades()
  local availableUpgrades = {
    {
        name = "Tempo Up",
        description = "Faster attacks and projectiles",
        apply = function()
          player.speedMul = (player.speedMul or 1) * MULT_STEP
          scaleOwnedAttacks(STAT_FIELDS.speed, MULT_STEP)
        end
    },
    {
        name = "Volume Up",
        description = "Bigger area for every attack",
        apply = function()
          player.areaMul = (player.areaMul or 1) * MULT_STEP
          scaleOwnedAttacks(STAT_FIELDS.area, MULT_STEP)
        end
    },
    {
        name = "Gain Up",
        description = "More damage from every attack",
        apply = function()
          player.damageMul = (player.damageMul or 1) * MULT_STEP
          scaleOwnedAttacks(STAT_FIELDS.damage, MULT_STEP)
        end
    },
    {
        name = "Chord Up",
        description = "More projectiles from every instrument",
        apply = function()
          player.quantityBonus = (player.quantityBonus or 0) + 1
          addToOwnedCount(1)
        end
    },
    {
        name = "BPM Up",
        description = "Speed up the music and your attacks",
        canOffer = function() return music and music.tempoMultiplier < 2 end,
        apply = function()
          music.tempoMultiplier = math.min(2, music.tempoMultiplier + 0.1)
        end
    },
    {
        name = "Delay Up",
        description = "Add echo to the song's instruments",
        canOffer = function() return music and (music.delayLevel or 0) < 3 end,
        apply = function()
          music.delayLevel = (music.delayLevel or 0) + 1
          music.setDelay(0.22 * music.delayLevel, 0.3 + 0.08 * music.delayLevel, 0.75)
        end
    },
    {
        name = "Size Up",
        description = "Increase player size",
        apply = function() player.r = player.r + 5 end
    },
    {
        name = "Enemy Slowdown",
        description = "Decrease enemy speed",
        apply = function()
            for _, enemy in ipairs(enemies) do
                enemy.speed = enemy.speed * 0.9
            end
        end
    },
    {
        name = "XP Boost",
        description = "Gain more XP from enemies",
        apply = function() player.xpMultiplier = (player.xpMultiplier or 1) + 0.2 end
    }
  }

  -- One freely choosable upgrade per instrument, in roster order.
  for entryIndex, entry in ipairs(roster.ENTRIES) do
    table.insert(availableUpgrades, addInstrumentUpgrade(entryIndex, entry))
  end

  return availableUpgrades
end

-- All music upgrades that can be offered right now.
local function eligibleMusicUpgrades()
  local list = {}
  for _, upgrade in ipairs(availableUpgrades) do
    if upgrade.musicUnlock and upgrade.canOffer() then
      list[#list + 1] = upgrade
    end
  end
  return list
end

function getRandomUpgrades(count)
  local pool = {}
  for _, upgrade in ipairs(availableUpgrades) do
    if upgrade.canOffer == nil or upgrade.canOffer() then
      table.insert(pool, upgrade)
    end
  end

  local choices = {}
  local indices = {}

  for i = 1, #pool do
      table.insert(indices, i)
  end

  for i = 1, count do
      if #indices == 0 then break end
      local randomIndex = love.math.random(#indices)
      table.insert(choices, pool[indices[randomIndex]])
      table.remove(indices, randomIndex)
  end

  -- Deterministic progression: while the level gate is open, a music upgrade
  -- is ALWAYS on the menu (a random eligible instrument is injected if the
  -- roll missed one).
  if levelGateOpen() then
    local hasMusic = false
    for _, choice in ipairs(choices) do
      if choice.musicUnlock then hasMusic = true end
    end
    if not hasMusic then
      local eligible = eligibleMusicUpgrades()
      if #eligible > 0 then
        if #choices == 0 then
          choices[1] = eligible[love.math.random(#eligible)]
        else
          choices[#choices] = eligible[love.math.random(#eligible)]
        end
      end
    end
  end

  return choices
end
