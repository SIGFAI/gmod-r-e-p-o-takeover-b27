-- R.E.P.O. Takeover: gold-plated loot with dollar values, an extraction point, robot workers,
-- gnome swarms and the Huntsman. Smash loot and it loses value; haul it to the green zone.
util.AddNetworkString("repo_pop")
util.AddNetworkString("repo_cheer")

Repo = Repo or {}
Repo.level = 1
Repo.haul = 0
Repo.quota = 6000
Repo.total = 0
Repo.zone = nil
Repo.ZONE_R = 120

-- model, name, value, scale
local LOOT = {
	{ "models/props_c17/FurnitureToilet001a.mdl", "Golden Toilet", 9000, 1 },
	{ "models/props_combine/breenglobe.mdl", "Tiny Globe", 4200, 1.8 },
	{ "models/props_c17/doll01.mdl", "Creepy Doll", 3100, 2.2 },
	{ "models/props_lab/huladoll.mdl", "Hula Doll", 2500, 2.6 },
	{ "models/props_lab/monitor01a.mdl", "Old Monitor", 3600, 1.5 },
	{ "models/gibs/hgibs.mdl", "Skull Trophy", 5200, 3 },
	{ "models/props_junk/watermelon01.mdl", "Cursed Melon", 1800, 2 },
	{ "models/props_interiors/Furniture_Lamp01a.mdl", "Fancy Lamp", 2800, 1.5 },
	{ "models/props_junk/garbage_coffeemug001a.mdl", "Royal Mug", 1200, 3.2 },
	{ "models/props_lab/harddrive02.mdl", "Data Brick", 2000, 3 },
	{ "models/props_junk/Shoe001a.mdl", "Lucky Shoe", 900, 3.2 },
	{ "models/props_c17/FurnitureWashingmachine001a.mdl", "Washing Machine", 6500, 0.8 },
	{ "models/props_c17/statue_horse.mdl", "Horse Statue", 14000, 0.45 },
}

local ROBOT_SKINS = { "sigf/robot", "sigf/robot_cyan", "sigf/robot_pink", "sigf/robot_lime" }

local function pop(pos, text, kind)
	net.Start("repo_pop")
	net.WriteVector(pos)
	net.WriteString(text)
	net.WriteUInt(kind, 3) -- 0 loss, 1 gain, 2 info
	net.Broadcast()
end

local function money(n) return "$" .. string.Comma(math.floor(n)) end

local function lootCount()
	local n = 0
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if e.repo and not e.repoGone then n = n + 1 end
	end
	return n
end

local function breakLoot(e)
	if not IsValid(e) or e.repoGone then return end
	e.repoGone = true
	local c = e:WorldSpaceCenter()
	Sigf.Effect("GlassImpact", c)
	Sigf.Effect("Explosion", c, { scale = 0.4, magnitude = 0.4 })
	Sigf.Sound("sigf/shatter.wav", c, 85, 100)
	pop(c + Vector(0, 0, 30), "SHATTERED! $0", 0)
	e:Remove()
end

local function hurtLoot(e, speed)
	if not IsValid(e) or e.repoGone then return end
	local max = e:GetNWInt("repo_max")
	local loss = math.floor(math.max(60, (speed - 200) * max / 1800))
	loss = math.min(loss, math.floor(max * 0.45))
	local v = e:GetNWInt("repo_value") - loss
	local c = e:WorldSpaceCenter()
	Sigf.Effect("Sparks", c, { magnitude = 2, scale = 2 })
	e:EmitSound("physics/metal/metal_solid_impact_hard" .. table.Random({ 1, 4, 5 }) .. ".wav", 75, math.random(110, 140))
	if v <= 0 then
		e:SetNWInt("repo_value", 0)
		breakLoot(e)
	else
		e:SetNWInt("repo_value", v)
		pop(c + Vector(0, 0, 24), "-" .. money(loss), 0)
	end
end

function Repo.SpawnLoot(pos, idx)
	local d = idx and LOOT[idx] or Sigf.Pick(LOOT)
	for _ = 1, 6 do
		if util.IsValidModel(d[1]) then break end
		d = Sigf.Pick(LOOT)
	end
	local e = Sigf.Prop(d[1], pos + Vector(0, 0, 24), d[4], 0)
	if not IsValid(e) then return nil end
	e.repo = true
	e:SetMaterial("models/player/shared/gold_player")
	local jitter = math.Rand(0.85, 1.25)
	local v = math.floor(d[3] * jitter / 50) * 50
	e:SetNWInt("repo_value", v)
	e:SetNWInt("repo_max", v)
	e:SetNWString("repo_name", d[2])
	e:AddCallback("PhysicsCollide", function(ent, data)
		if data.Speed < 320 or (ent.repoCool or 0) > CurTime() then return end
		ent.repoCool = CurTime() + 0.3
		local speed = data.Speed
		timer.Simple(0, function() hurtLoot(ent, speed) end)
	end)
	local phys = e:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetMass(math.Clamp(phys:GetMass(), 8, 30)) -- light enough to carry and throw
		phys:Wake()
	end
	return e
end

---------------------------------------------------------------- extraction zone
local function pickZone()
	local c = Sigf.Arena()
	local p = Sigf.Ground(c, 550)
	for _ = 1, 8 do
		if p:Distance(c) > 250 then break end
		p = Sigf.Ground(c, 550)
	end
	Repo.zone = p
	SetGlobalVector("repo_zone", p)
end

local function syncGlobals()
	SetGlobalInt("repo_haul", Repo.haul)
	SetGlobalInt("repo_quota", Repo.quota)
	SetGlobalInt("repo_level", Repo.level)
end

local function fillLoot(n)
	local c = Sigf.Arena()
	for i = 1, n do
		Sigf.After(i * 0.12, function()
			local p = Sigf.Ground(c, 800)
			if Repo.zone and p:Distance(Repo.zone) < 220 then return end
			local e = Repo.SpawnLoot(p)
			if IsValid(e) then Sigf.Effect("propspawn", e:GetPos()) end
		end)
	end
end

local function celebrate()
	local z = Repo.zone
	Sigf.Focus(z, 6)
	Sigf.Text("QUOTA REACHED!", 4, { color = Color(120, 255, 120), y = 0.8 })
	net.Start("repo_cheer") net.Broadcast()
	for i = 1, 14 do
		Sigf.After(i * 0.15, function()
			Sigf.Effect("balloon_pop", z + Vector(math.random(-110, 110), math.random(-110, 110), math.random(20, 160)), { color = math.random(0, 7) })
		end)
	end
	Sigf.After(5, function()
		Repo.level = Repo.level + 1
		Repo.haul = 0
		Repo.quota = math.floor(Repo.quota * 1.5 / 500) * 500
		if not Repo.keepZone then pickZone() end
		syncGlobals()
		Sigf.Text("LEVEL " .. Repo.level .. ": NEW EXTRACTION POINT", 4, { y = 0.8 })
		if not Repo.keepZone then fillLoot(6) end
		Sigf.Battle.combine = math.min(3, 1 + math.floor(Repo.level / 2))
	end)
end

local function extractTick()
	local z = Repo.zone
	if not z then return end
	for _, e in ipairs(ents.FindInSphere(z + Vector(0, 0, 30), Repo.ZONE_R)) do
		if e.repo and not e.repoGone and not e:IsPlayerHolding() then
			e.repoGone = true
			local v = e:GetNWInt("repo_value")
			local c = e:WorldSpaceCenter()
			Repo.haul = Repo.haul + v
			Repo.total = Repo.total + v
			e:SetNotSolid(true)
			e:SetMoveType(MOVETYPE_NONE)
			Sigf.Scale(e, 0.05, 0.5)
			SafeRemoveEntityDelayed(e, 0.6)
			Sigf.Sound("sigf/chaching.wav", c, 90, 100)
			Sigf.Effect("cball_explode", c)
			Sigf.Sprite("sigf/dollar", c + Vector(0, 0, 110), 24, 1.2)
			pop(c + Vector(0, 0, 40), "+" .. money(v), 1)
			Sigf.Focus(z, 3)
			syncGlobals()
		end
	end
	if Repo.haul >= Repo.quota and not Repo.done then
		Repo.done = true
		celebrate()
		Sigf.After(6, function() Repo.done = false end)
	end
end

---------------------------------------------------------------- robot workers (players)
local function clearRobot(p)
	for _, e in ipairs(p.repoParts or {}) do if IsValid(e) then e:Remove() end end
	p.repoParts = nil
end

local function buildRobot(p)
	clearRobot(p)
	if Sigf.IsCamera(p) or not p:Alive() then return end
	p:SetNoDraw(true)
	p:DrawShadow(false)
	local skin = ROBOT_SKINS[(p:EntIndex() % #ROBOT_SKINS) + 1]
	p.repoParts = {}
	local function part(model, lp, scale, mat, color, ang, role)
		local e = ents.Create("prop_dynamic")
		e:SetModel(model)
		e:SetPos(p:GetPos())
		e:SetParent(p)
		e:Spawn()
		e:SetLocalPos(lp * 0.8)
		e:SetLocalAngles(ang or Angle(0, 0, 0))
		e:SetModelScale(scale * 0.8, 0)
		e:SetSolid(SOLID_NONE)
		if mat then e:SetMaterial(mat) end
		if color then e:SetColor(color) end
		e.repoBase = lp * 0.8
		e.repoRole = role
		p.repoParts[#p.repoParts + 1] = e
		return e
	end
	local ball, eye, cube = "models/hunter/misc/sphere1x1.mdl", "models/hunter/misc/sphere025x025.mdl", "models/hunter/blocks/cube025x025x025.mdl"
	part(ball, Vector(0, 0, 33), 1.3, skin, nil, nil, "body")
	for _, side in ipairs({ -1, 1 }) do
		part(eye, Vector(24, 11 * side, 42), 1.7, "models/debug/debugwhite", nil, nil, "body")
		part(eye, Vector(32, 11 * side, 42), 0.9, "models/debug/debugwhite", Color(10, 10, 10), nil, "body")
		part(eye, Vector(0, 15 * side, 6), 1.5, "models/debug/debugwhite", Color(40, 40, 40), nil, "foot" .. side)
		part(eye, Vector(2, 33 * side, 28), 1.2, "models/debug/debugwhite", Color(60, 60, 60), nil, "hand" .. side) -- hands
	end
	local bulb = part(eye, Vector(0, 0, 68), 0.9, "models/debug/debugwhite", Color(255, 60, 60), nil, "body")
	bulb:SetKeyValue("renderfx", "16") -- glow
end


-- robots hop while walking and raise their hands while carrying loot
local function carrying(p) return p.repoCarry or (p.repoJob and p.repoJob.stage == "carry") end
timer.Create("repo_robot_anim", 0.08, 0, function()
	local t = CurTime()
	for _, p in ipairs(player.GetAll()) do
		if p.repoParts and p:Alive() then
			local moving = p:GetVelocity():Length2D() > 40
			local hop = moving and math.abs(math.sin(t * 11)) * 5 or 0
			local sway = moving and math.sin(t * 11) * 8 or 0
			local up = carrying(p)
			for _, e in ipairs(p.repoParts) do
				if IsValid(e) and e.repoBase then
					local b = e.repoBase
					local r = e.repoRole
					if r == "body" then
						e:SetLocalPos(b + Vector(0, 0, hop))
					elseif r == "hand-1" or r == "hand1" then
						local side = (r == "hand1") and 1 or -1
						if up then e:SetLocalPos(Vector(8, b.y * 0.8, 62 + math.sin(t * 8) * 3)) else e:SetLocalPos(b + Vector(0, 0, hop) + Vector(sway * side, 0, 0)) end
					elseif r == "foot-1" or r == "foot1" then
						local side = (r == "foot1") and 1 or -1
						e:SetLocalPos(b + Vector(sway * side * 0.8, 0, math.max(0, sway * side * 0.5)))
					end
				end
			end
		end
	end
end)

hook.Add("PlayerSpawn", "repo_robot", function(p)
	timer.Simple(0.5, function() if IsValid(p) then buildRobot(p) end end)
end)

hook.Add("PostPlayerDeath", "repo_robot_die", function(p)
	if p.repoParts then
		Sigf.Effect("Explosion", p:WorldSpaceCenter(), { scale = 0.5, magnitude = 0.5 })
		Sigf.Effect("ManhackSparks", p:WorldSpaceCenter())
	end
	clearRobot(p)
end)


---------------------------------------------------------------- bot robots haul loot to the zone
local function dropJob(p, cd)
	p.repoJob = nil
	p.SigfManual = false
	p.repoCool = CurTime() + (cd or 6)
end

hook.Add("StartCommand", "repo_haul_bots", function(p, cmd)
	local job = p.repoJob
	if not job or not p:IsBot() then return end
	cmd:ClearButtons()
	cmd:ClearMovement()
	local it = job.item
	if Repo.noHaul then dropJob(p, 60) return end
	if not p:Alive() or not IsValid(it) or it.repoGone or CurTime() > job.die then dropJob(p) return end
	local target = it:GetPos()
	if job.stage == "carry" then
		target = Repo.zone or target
		local phys = it:GetPhysicsObject()
		if IsValid(phys) then
			local want = p:GetPos() + Vector(0, 0, 100) + Angle(0, p:EyeAngles().y, 0):Forward() * 30
			phys:Wake()
			phys:SetVelocity((want - it:GetPos()) * 12)
		end
		if (target - p:GetPos()):Length2D() < 100 then
			if IsValid(phys) then phys:SetVelocity(Vector(0, 0, 0)) end
			it:SetPos((Repo.zone or it:GetPos()) + Vector(0, 0, 50))
			dropJob(p, 8)
			return
		end
	elseif (target - p:GetPos()):Length2D() < 70 then
		job.stage = "carry"
		Sigf.Sprite("sigf/dollar", p, 36, 1.5)
	end
	local ang = (target - p:GetPos()):Angle()
	ang.p = 0
	cmd:SetViewAngles(ang)
	p:SetEyeAngles(ang)
	cmd:SetForwardMove(260)
	if p:GetVelocity():Length2D() < 25 then cmd:SetButtons(IN_JUMP) end
end)

-- the stream camera likes the robots: follow a hauler, otherwise any robot
Sigf.After(10, function()
	Sigf.Every(9, function()
		local pick
		for _, p in ipairs(player.GetBots()) do
			if p:Alive() and (p.repoJob or not pick) then pick = p end
		end
		if pick then Sigf.Focus(pick, 7) end
	end)
end)

Sigf.After(6, function()
	Sigf.Every(1.5, function()
		if not Repo.zone then return end
		for _, p in ipairs(player.GetBots()) do
			if not Repo.noHaul and p:Alive() and not p.repoJob and CurTime() > (p.repoCool or 0) then
				local danger = #Sigf.Near(p:GetPos(), 450, function(e) return e:IsNPC() end) > 0
				if not danger then
					local best, bd
					for _, e in ipairs(ents.FindByClass("prop_physics")) do
						if e.repo and not e.repoGone and not e.repoTaken and e:GetPos():Distance(Repo.zone) > 160 then
							local d = e:GetPos():DistToSqr(p:GetPos())
							if d < 1800 ^ 2 and (not bd or d < bd) then best, bd = e, d end
						end
					end
					if best then
						p.repoJob = { item = best, stage = "fetch", die = CurTime() + 30 }
						p.SigfManual = true
					end
				end
			end
		end
		-- a hauler that meets an enemy lets go and fights
		for _, p in ipairs(player.GetBots()) do
			if p.repoJob and #Sigf.Near(p:GetPos(), 350, function(e) return e:IsNPC() end) > 0 then dropJob(p, 5) end
		end
	end)
end)

---------------------------------------------------------------- monsters
local function tag(e, text)
	e:SetNWString("repo_tag", text)
end

function Repo.Huntsmanize(e)
	e:SetModelScale(1.3, 0)
	e:SetColor(Color(135, 135, 160))
	e:SetMaxHealth(350)
	e:SetHealth(350)
	tag(e, "HUNTSMAN")
	Sigf.Sprite("sprites/light_glow02_add", e, 28, 0, { color = Color(255, 40, 40), offset = Vector(0, 0, 100) })
	Sigf.Sound("npc/combine_soldier/vo/onedown.wav", e:GetPos(), 80, 60)
end

hook.Add("SigfBattleSpawn", "repo_huntsman", function(e, side)
	if side == "combine" then Repo.Huntsmanize(e) end
end)

local function gnomeHat(e)
	local hat = ents.Create("prop_dynamic")
	hat:SetModel("models/props_junk/TrafficCone001a.mdl")
	hat:SetPos(e:GetPos())
	hat:Spawn()
	hat:SetModelScale(0.8, 0)
	hat:SetColor(Color(255, 40, 40))
	hat:SetSolid(SOLID_NONE)
	local bone = e:LookupBone("ValveBiped.Bip01_Head1")
	if bone then
		hat:FollowBone(e, bone)
		hat:SetLocalPos(Vector(4, 0, 0))
		hat:SetLocalAngles(Angle(0, -90, -90))
	else
		hat:SetParent(e)
		hat:SetLocalPos(Vector(0, 0, 40))
	end
	e:DeleteOnRemove(hat)
end

function Repo.SpawnGnome(pos)
	local e = Sigf.NPC("npc_fastzombie", pos, { health = 40, scale = 0.8, life = 120 })
	if not IsValid(e) then return end
	e:SetColor(Color(150, 255, 90))
	e.repoGnome = true
	tag(e, "GNOME")
	gnomeHat(e)
	return e
end

local function gnomeCount()
	local n = 0
	for _, e in ipairs(ents.FindByClass("npc_fastzombie")) do if e.repoGnome and e:Health() > 0 then n = n + 1 end end
	return n
end

local function gnomeWave()
	if Repo.noWave then return end
	if gnomeCount() > 3 then return end
	local c = Sigf.Arena()
	local centre = Sigf.Ground(c, 800)
	local n = 3 + math.min(Repo.level, 2)
	for i = 1, n do
		Sigf.After(i * 0.3, function()
			local g = Repo.SpawnGnome(Sigf.Ground(centre, 150))
			if IsValid(g) then Sigf.Effect("ThumperDust", g:GetPos(), { scale = 1 }) end
		end)
	end
	Sigf.Sound("sigf/gnome.wav", centre, 95, 100)
end

hook.Add("OnNPCKilled", "repo_kill", function(npc, attacker)
	local c = npc:WorldSpaceCenter()
	if npc.repoGnome then
		Sigf.Effect("BloodImpact", c)
		Sigf.Sound("sigf/gnome.wav", c, 80, 160)
	elseif npc:GetNWString("repo_tag") == "HUNTSMAN" then
		Sigf.Effect("Explosion", c, { scale = 0.6, magnitude = 0.6 })
		Sigf.Text("HUNTSMAN DOWN", 3, { color = Color(255, 90, 90), y = 0.8 })
		-- drops a trophy worth a fortune
		local e = Repo.SpawnLoot(npc:GetPos())
		if IsValid(e) then e:SetNWInt("repo_value", 7500) e:SetNWInt("repo_max", 7500) e:SetNWString("repo_name", "Huntsman's Mask") end
	end
end)

-- Every hit shows: knockback and a pain popup on monsters.
hook.Add("EntityTakeDamage", "repo_hits", function(target, dmg)
	if target:IsNPC() and (target:GetNWString("repo_tag") ~= "" or target.repoGnome) then
		dmg:SetDamageForce(dmg:GetDamageForce() * 3)
		-- one summed number per target every 0.35 s
		target.repoAcc = (target.repoAcc or 0) + dmg:GetDamage()
		if CurTime() > (target.repoPopT or 0) then
			target.repoPopT = CurTime() + 0.35
			pop(target:WorldSpaceCenter() + Vector(0, 0, 30), "-" .. math.floor(target.repoAcc), 2)
			target.repoAcc = 0
		end
	end
end)

---------------------------------------------------------------- start
Sigf.Battle.rebels = 0
Sigf.Battle.radius = 800
Sigf.Battle.combine = 1
Sigf.Battle.combineWeapons = { "weapon_shotgun" }

Sigf.After(1, function()
	pickZone()
	syncGlobals()
	fillLoot(14)
	if not Sigf.IsDemo() then
		Sigf.Text("R.E.P.O. TAKEOVER", 4, { y = 0.8 })
		Sigf.After(4, function() Sigf.Text("Haul the loot to the green zone", 4, { size = 40, y = 0.86 }) end)
	end
	Sigf.Every(0.3, extractTick)
	Sigf.Every(5, function()
		if lootCount() < 12 then
			local e = Repo.SpawnLoot(Sigf.Ground(Sigf.Arena(), 800))
			if IsValid(e) then Sigf.Effect("propspawn", e:GetPos()) end
		end
	end)
	Sigf.After(8, gnomeWave)
	Sigf.Every(32, gnomeWave)
end)
