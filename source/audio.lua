function handleSound(dt)
  soundTime = soundTime + dt
	if soundTime >= bpm / 60 then
		currentSound:play()
    loop = loop + 1
    if loop > 2 then
      currentSound = hi_hat
    end
		soundTime = 0 --optional if you want it to happen repeatedly
	end

end