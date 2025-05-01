function generateUpgrades()
  local availableUpgrades = {
    {
        name = "Tempo Up",
        description = "Increase movement speed",
        apply = function() 
          for _, k in pairs(player.attacks) do
            k.speed = k.speed  + k.speed * .1
          end
         end
    },
    {
        name = "BPM Up",
        description = "Increase attack speed",
        apply = function() player.bpm = player.bpm + 10 end
    },
    {
        name = "Range Up",
        description = "Increase attack range",
        apply = function()
          for _, k in pairs(player.attacks) do
            k.radius = k.radius + 5
          end
        end
    },
    {
        name = "Size Up",
        description = "Increase player size",
        apply = function() player.r = player.r + 5 end
    },
    {
      name = "Quantity Up",
      description = "Increase attack quantity",
      apply = function ()
        for _, k in pairs(player.attacks) do
            k.count  = k.count + 1
        end
      end
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

  table.insert(availableUpgrades, {
    name = "Knife Bounces",
    description = "Increase number of bounces before destroying",
    apply = function() 
        for _, attack in ipairs(player.attacks) do
            if attack == attacks[4] then
                attack.maxBounces = attack.maxBounces + 2
            end
        end
    end
})

  -- after Bouncing Knife Attack get max level
  --[[ table.insert(availableUpgrades, {
    name = "Knife Penetration",
    description = "Increase number of enemies each knife can hit",
    apply = function() 
        for _, attack in ipairs(player.attacks) do
            if attack == attacks[4] then
                attack.penetration = attack.penetration + 1
            end
        end
    end
}) ]]

  return availableUpgrades
end

function getRandomUpgrades(count)
  local choices = {}
  local indices = {}
  
  for i = 1, #availableUpgrades do
      table.insert(indices, i)
  end
  
  for i = 1, count do
      if #indices == 0 then break end
      local randomIndex = love.math.random(#indices)
      table.insert(choices, availableUpgrades[indices[randomIndex]])
      table.remove(indices, randomIndex)
  end
  
  return choices
end