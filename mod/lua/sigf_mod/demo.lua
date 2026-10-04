-- Demo: loot with a price, carry it to the zone, smash one, gnome swarm, Huntsman, quota.
local Z = {} -- scene state

-- Holds a loot item above and in front of the player (like the physics gun carry) until released.
local function carry(item)
	local h = Sigf.Host()
	if not IsValid(h) or not IsValid(item) then return end
	Z.item = item
	h.repoCarry = true
	timer.Create("repo_demo_carry", 0.03, 0, function()
		local it = Z.item
		if not IsValid(it) or not IsValid(h) then timer.Remove("repo_demo_carry") return end
		local phys = it:GetPhysicsObject()
		if not IsValid(phys) then return end
		local want = h:EyePos() + h:EyeAngles():Forward() * 85 + Vector(0, 0, 42)
		if Z.dest and (Z.dest - h:GetPos()):Length2D() < 220 then want = Z.dest + Vector(0, 0, 55) end
		if not Z.fragile then it.repoCool = CurTime() + 0.6 end
		phys:Wake()
		phys:SetVelocity((want - it:GetPos()) * 12)
		phys:SetAngleVelocity(Vector(0, 40, 0))
	end)
end

local function release(vel)
	local hh = Sigf.Host()
	if IsValid(hh) then hh.repoCarry = false end
	Z.dest = nil
	timer.Remove("repo_demo_carry")
	local it = Z.item
	Z.item = nil
	if IsValid(it) and vel then
		local phys = it:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() phys:SetVelocity(vel) end
	end
end

-- Walks the player (carrying) to a point; done() when there.
local function walkTo(dest, done, timeout)
	local t0 = CurTime()
	Z.dest = dest
	Sigf.Pilot(false)
	local name = "repo_demo_walk"
	timer.Create(name, 0.15, 0, function()
		local h = Sigf.Host()
		if not IsValid(h) then timer.Remove(name) return end
		local d = (dest - h:GetPos()):Length2D()
		if d < 90 or CurTime() - t0 > (timeout or 12) then
			timer.Remove(name)
			if done then done() end
			return
		end
		Sigf.LookAt(dest + Vector(0, 0, 40), 0.3)
		Sigf.Walk(0.3, 220)
		if h:GetVelocity():Length2D() < 20 then Sigf.Jump() end
	end)
end

-- Faces the most open direction.
local function faceOpen()
	local h = Sigf.Host()
	local bestYaw, bestF = 0, -1
	for yaw = 0, 330, 30 do
		local dir = Angle(0, yaw, 0):Forward()
		local a = h:GetPos() + Vector(0, 0, 40)
		local tr = util.TraceLine({ start = a, endpos = a + dir * 1100, mask = MASK_SOLID_BRUSHONLY })
		if tr.Fraction > bestF then bestYaw, bestF = yaw, tr.Fraction end
	end
	h:SetEyeAngles(Angle(0, bestYaw, 0))
end

-- Open view, extraction point ahead, loot (list of model indexes) close in front.
local function stage(zoneDist, picks)
	Sigf.Pilot(false)
	release()
	faceOpen()
	local h = Sigf.Host()
	local zone = Sigf.Front(zoneDist)
	Repo.zone = zone
	SetGlobalVector("repo_zone", zone)
	Z.zone = zone
	local right = h:EyeAngles():Right()
	local out = {}
	for i, idx in ipairs(picks) do
		local off = (i - (#picks + 1) / 2) * 95
		local e = Repo.SpawnLoot(Sigf.Front(230) + right * off, idx)
		if IsValid(e) then out[#out + 1] = e Sigf.Effect("propspawn", e:GetPos()) end
	end
	return out
end


local TXT = { y = 0.8 }
local function say(t, sec, col, size) Sigf.Text(t, sec, { y = 0.8, size = size or 48, color = col }) end

-- deliver one piece of loot into the zone
local function deliver(it)
	if not IsValid(it) then return end
	Sigf.LookAt(it, 0.6)
	Sigf.After(0.6, function()
		carry(it)
		walkTo(Z.zone, function() release(Vector(0, 0, 0)) end, 8)
	end)
end

Sigf.Demo(0.3, function()
	Repo.noWave = true
	Repo.noHaul = true
	Repo.keepZone = true
	Repo.haul = 0
	SetGlobalInt("repo_haul", 0)
	Sigf.Battle.combine = 0 -- no stray Huntsman until his own moment
	for _, n in ipairs(Sigf.NPCs()) do if n:Disposition(Sigf.Host()) == D_HT then n:Remove() end end
	Z.loot = stage(480, { 1, 6, 5 }) -- toilet, monitor, skull
	Sigf.LookAt(Sigf.Front(260) + Vector(0, 0, 40), 2)
	say("R.E.P.O. TAKEOVER", 3, Color(255, 230, 80), 60)
end)

-- Moment 1: carry loot into the green zone: cha-ching, quota reached, balloons.
Sigf.Demo(2.2, function()
	say("Haul gold loot to the green zone", 5, Color(120, 255, 140))
	deliver(Z.loot[1])
end)

-- Funny moment: a loot shower that shatters on the ground, with screen shake.
Sigf.Demo(9, function()
	say("LOOT SHOWER! Mind the prices!", 4, Color(255, 230, 80), 52)
	local h = Sigf.Host()
	Sigf.Shake(h:GetPos(), 6, 3)
	for i = 1, 9 do
		Sigf.After(i * 0.25, function()
			local p = Sigf.Front(math.random(250, 550)) + h:EyeAngles():Right() * math.random(-250, 250) + Vector(0, 0, 450)
			local e = Repo.SpawnLoot(p)
			if IsValid(e) then
				local ph = e:GetPhysicsObject()
				if IsValid(ph) then ph:SetVelocity(Vector(0, 0, -900)) end
			end
		end)
	end
end)

-- A giant Huntsman jump-scare, shot down; he drops his mask.
Sigf.Demo(15, function()
	say("THE HUNTSMAN!", 4, Color(255, 60, 60), 64)
	Sigf.Pilot(false)
	faceOpen()
	local h = Sigf.Host()
	local e = Sigf.NPC("npc_combine_s", Sigf.Front(420), { weapon = "weapon_shotgun" })
	if IsValid(e) then
		Repo.Huntsmanize(e)
		e:SetModelScale(1.9, 0)
		e:SetAngles(Angle(0, (h:GetPos() - e:GetPos()):Angle().y, 0))
		Z.hunt = e
		Sigf.Focus(e, 3)
		Sigf.LookAt(e, 1)
		Sigf.Shake(e:GetPos(), 10, 1.5)
		Sigf.Sound2D("sigf/gnome.wav")
	end
	Sigf.After(1.2, function() Sigf.Pilot(true) end)
	Sigf.After(7, function()
		if IsValid(Z.hunt) and Z.hunt:Health() > 0 then Sigf.KillByHost(Z.hunt) end
	end)
end)

-- Gnome swarm.
Sigf.Demo(25, function()
	release()
	say("GNOMES! Shoot them!", 4, Color(255, 90, 90), 60)
	faceOpen()
	Sigf.Pilot(true)
	local h = Sigf.Host()
	local right = h:EyeAngles():Right()
	for i = 1, 6 do
		Sigf.After(i * 0.2, function()
			local g = Repo.SpawnGnome(Sigf.Front(550) + right * (i * 60 - 180))
			if IsValid(g) then Sigf.Effect("ThumperDust", g:GetPos()) end
		end)
	end
	Sigf.Sound2D("sigf/gnome.wav")
end)

-- Slam loot into the ground and watch the price fall.
Sigf.Demo(35, function()
	Z.fragile = true
	say("Rough handling costs money!", 6, Color(255, 110, 80))
	Z.loot = stage(900, { 6, 1 })
	local it = Z.loot[1]
	if IsValid(it) then
		Sigf.LookAt(it, 1)
		Sigf.After(0.8, function()
			carry(it)
			Sigf.LookAt(Sigf.Front(170), 3)
			Sigf.After(1.0, function()
				local hh = Sigf.Host()
				release(hh:EyeAngles():Forward() * 300 + Vector(0, 0, -1100))
			end)
			Sigf.After(2.6, function() if IsValid(it) then carry(it) end end)
			Sigf.After(3.6, function()
				local hh = Sigf.Host()
				if IsValid(it) then release(hh:EyeAngles():Forward() * 300 + Vector(0, 0, -1200)) end
			end)
		end)
	end
end)

-- Haul the mask into the zone: next quota reached.
Sigf.Demo(47, function()
	Z.fragile = false
	Repo.haul = Repo.quota - 7000
	SetGlobalInt("repo_haul", Repo.haul)
	say("One last piece: reach the quota!", 5, Color(120, 255, 140))
	local it
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if e.repo and not e.repoGone and e:GetNWString("repo_name") == "Huntsman's Mask" then it = e end
	end
	Sigf.Pilot(false)
	faceOpen()
	local z = Sigf.Front(330)
	Repo.zone = z
	SetGlobalVector("repo_zone", z)
	Z.zone = z
	if not IsValid(it) then it = Repo.SpawnLoot(Sigf.Front(200), 5) end
	if IsValid(it) then
		it:SetNWInt("repo_value", 8000)
		it:SetNWInt("repo_max", 8000)
		it:SetNWString("repo_name", "Huntsman's Mask")
		it.repoCool = CurTime() + 20
		Sigf.Effect("propspawn", it:GetPos())
		deliver(it)
	end
end)

-- Finale: a bigger swarm.
Sigf.Demo(60, function()
	say("MORE GNOMES!", 4, Color(255, 215, 60), 56)
	release()
	faceOpen()
	Sigf.Pilot(true)
	local h = Sigf.Host()
	local right = h:EyeAngles():Right()
	for i = 1, 8 do
		Sigf.After(i * 0.25, function()
			local g = Repo.SpawnGnome(Sigf.Front(500) + right * (i * 50 - 200))
			if IsValid(g) then Sigf.Effect("ThumperDust", g:GetPos()) end
		end)
	end
end)
