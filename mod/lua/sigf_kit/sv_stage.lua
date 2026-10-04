-- $MOD kit: stream stage, server side (frozen). Only when play.ps1 has written data/sigf/stage.txt.
--   idle / mod : NPCs (Combine vs rebels) and bots fight in the arena; the stream player is an
--                invisible camera circling the action (cl_stage.lua).
--   demo       : the stream player plays (third person, invincible), piloted between the mod's Sigf.Demo steps.
--   setup      : one-time install (model/sound/NPC lists, map navmesh).
-- Lines read by check.ps1 / preview.ps1 / setup.ps1 in console.log: SIGF_BOOT, SIGF_READY, SIGF_NOMOD,
-- SIGF_ERROR, SIGF_SHOWCASE_READY, SIGF_DEMO_START, SIGF_SETUP_DONE.
local stage = Sigf.Stage()

---------------------------------------------------------------- demo: mod API (no effect outside the demo)
Sigf.Steps = Sigf.Steps or {}
Sigf.PilotOn = true
local manual = { walkUntil = 0, shootUntil = 0, jumpUntil = 0, lookUntil = 0, speed = 200 }

-- Script step, sec seconds after the recording starts.
function Sigf.Demo(sec, fn) Sigf.Steps[#Sigf.Steps + 1] = { sec = sec, fn = fn } end
-- Autopilot (walks toward enemies and shoots): true/false.
function Sigf.Pilot(on) Sigf.PilotOn = on and true or false end
function Sigf.Walk(sec, speed) manual.walkUntil = CurTime() + (sec or 1) manual.speed = speed or 200 end
function Sigf.Shoot(sec) manual.shootUntil = CurTime() + (sec or 1) end
function Sigf.Jump() manual.jumpUntil = CurTime() + 0.25 end

local function targetPos(t)
	if isentity(t) then return IsValid(t) and t:WorldSpaceCenter() or nil end
	return t
end

-- Turns the stream player's view toward a position or an entity (and holds it 3 s).
function Sigf.LookAt(target, sec)
	manual.look = target
	manual.lookUntil = CurTime() + (sec or 3)
	local h = Sigf.Host()
	local p = targetPos(target)
	if IsValid(h) and p then h:SetEyeAngles((p - h:EyePos()):Angle()) end
end

-- Ground point dist units in front of the stream player.
function Sigf.Front(dist)
	local h = Sigf.Host()
	if not IsValid(h) then return Sigf.Action() end
	local fwd = h:EyeAngles():Forward()
	fwd.z = 0
	fwd:Normalize()
	local want = h:GetPos() + fwd * (dist or 300)
	local tr = util.TraceLine({ start = h:GetPos() + Vector(0, 0, 40), endpos = want + Vector(0, 0, 40), filter = h, mask = MASK_SOLID_BRUSHONLY })
	local p = tr.HitPos - fwd * 32
	local down = util.TraceLine({ start = p, endpos = p - Vector(0, 0, 2048), mask = MASK_SOLID_BRUSHONLY })
	return down.HitPos + Vector(0, 0, 2)
end

function Sigf.Give(class)
	local h = Sigf.Host()
	if not IsValid(h) then return end
	h:Give(class)
	h:SelectWeapon(class)
end

local function hostile(e, h)
	return IsValid(e) and e:IsNPC() and e:Health() > 0 and IsValid(h) and e:Disposition(h) == D_HT
end

-- Brings a living enemy NPC dist units in front of the player (otherwise spawns one), returns it.
function Sigf.BringNPC(dist, class)
	local h = Sigf.Host()
	if not IsValid(h) then return nil end
	local pos = Sigf.Front(dist or 350)
	local list = {}
	for _, e in ipairs(Sigf.NPCs()) do
		if hostile(e, h) and (not class or e:GetClass() == class) then list[#list + 1] = e end
	end
	local e = Sigf.Pick(list)
	if e then Sigf.Teleport(e, pos, Vector(0, 0, 0)) else e = Sigf.NPC(class or "npc_combine_s", pos, { weapon = "weapon_smg1" }) end
	if IsValid(e) then e:SetAngles(Angle(0, (h:GetPos() - pos):Angle().y, 0)) end
	return e
end

-- The stream player kills ent (death hooks see the player as the killer).
function Sigf.KillByHost(ent)
	local h = Sigf.Host()
	if IsValid(ent) and IsValid(h) then ent:TakeDamage(ent:Health() + 1000, h, h:GetActiveWeapon()) end
end

-- Stream camera (outside the demo): looks at target (entity or position) for sec seconds.
local focusUntil = 0
local function applyFocus(t)
	if isentity(t) and IsValid(t) then
		SetGlobalEntity("sigf_focus", t)
		Sigf.FocusPos = t:GetPos()
	elseif isvector(t) then
		SetGlobalEntity("sigf_focus", NULL)
		Sigf.FocusPos = t
	end
	if Sigf.FocusPos then SetGlobalVector("sigf_focus_pos", Sigf.FocusPos) end
end
function Sigf.Focus(target, sec)
	Sigf.ForcedFocus = target
	focusUntil = CurTime() + (sec or 6)
	applyFocus(target)
end

-- Stage battle settings. The mod can change them (Sigf.Battle.enabled = false to stop it).
Sigf.Battle = {
	enabled = true, combine = 4, rebels = 3, bots = 3, radius = 1200,
	combineClass = "npc_combine_s", combineWeapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun" },
	rebelWeapons = { "weapon_smg1", "weapon_ar2", "weapon_shotgun" },
}
-- Arena center per map, to pin it (otherwise computed: large flat navmesh area).
Sigf.Arenas = Sigf.Arenas or {}

if stage == "home" then return end

---------------------------------------------------------------- startup, hot reload, heartbeat
file.CreateDir("sigf")
local function readData(name) return string.Trim(file.Read("sigf/" .. name, "DATA") or "") end
local bootNonce = readData("cmd.txt")
print("SIGF_BOOT " .. bootNonce .. " stage=" .. stage .. " map=" .. game.GetMap())

-- check.ps1 copies the mod again then writes a new number in cmd.txt: reload the map (all Lua is reread).
timer.Create("sigf_cmd", 0.5, 0, function()
	file.Write("sigf/alive.txt", tostring(os.time()))
	local n = readData("cmd.txt")
	if n ~= "" and n ~= bootNonce then
		bootNonce = n
		print("SIGF_RELOAD " .. n)
		RunConsoleCommand("changelevel", game.GetMap())
	end
end)

hook.Add("SigfReady", "sigf_stage_ready", function()
	if stage == "mod" or stage == "demo" then
		print(Sigf.ModState == "ok" and "SIGF_READY" or "SIGF_NOMOD")
	else
		print("SIGF_READY_" .. string.upper(stage))
	end
end)

---------------------------------------------------------------- one-time install
if stage == "setup" then
	local function walk(dir, exts, out, strip)
		local files, dirs = file.Find(dir .. "*", "GAME")
		for _, f in ipairs(files or {}) do
			local ext = string.GetExtensionFromFilename(f)
			if ext and exts[string.lower(ext)] then out[#out + 1] = string.sub(dir .. f, strip + 1) end
		end
		for _, d in ipairs(dirs or {}) do walk(dir .. d .. "/", exts, out, strip) end
	end
	hook.Add("InitPostEntity", "sigf_setup", function()
		timer.Simple(3, function()
			local models, sounds, npcs, weapons = {}, {}, {}, {}
			walk("models/", { mdl = true }, models, 0)
			walk("sound/", { wav = true, mp3 = true, ogg = true }, sounds, 6)
			for k, v in pairs(list.Get("NPC")) do
				npcs[#npcs + 1] = k .. " | class " .. tostring(v.Class) .. " | weapons " .. table.concat(v.Weapons or {}, ",") .. " | " .. tostring(v.Category)
			end
			for k in pairs(list.Get("Weapon")) do weapons[#weapons + 1] = k end
			for name, t in pairs({ models = models, sounds = sounds, npcs = npcs, weapons = weapons }) do
				table.sort(t)
				file.Write("sigf/catalog_" .. name .. ".txt", table.concat(t, "\n"))
				print("SIGF_CATALOG " .. name .. " " .. #t)
			end
			if navmesh.IsLoaded() then
				print("SIGF_SETUP_DONE navmesh " .. #navmesh.GetAllNavAreas() .. " areas")
				return
			end
			print("SIGF_NAV_GENERATING")
			RunConsoleCommand("nav_generate")
			timer.Create("sigf_nav", 3, 0, function()
				if navmesh.IsGenerating() then return end
				if navmesh.IsLoaded() then
					navmesh.Save()
					timer.Remove("sigf_nav")
					print("SIGF_SETUP_DONE navmesh " .. #navmesh.GetAllNavAreas() .. " areas")
				end
			end)
		end)
	end)
	return
end

---------------------------------------------------------------- arena
local function computeArena()
	if Sigf.Arenas[game.GetMap()] then return Sigf.Arenas[game.GetMap()] end
	local spawn = ents.FindByClass("info_player_start")[1]
	local sp = IsValid(spawn) and spawn:GetPos() or Vector(0, 0, 0)
	if not navmesh.IsLoaded() then return sp end
	-- The most open area: the one with the most navmesh surface around it (stable choice from one launch to the next).
	local all = navmesh.GetAllNavAreas()
	local step = math.max(1, math.floor(#all / 80))
	local best, bestScore = sp, -1
	for i = 1, #all, step do
		local a = all[i]
		if not a:IsUnderwater() then
			local c = a:GetCenter()
			local score = 0
			for _, b in ipairs(navmesh.Find(c, 700, 100, 100)) do score = score + b:GetSizeX() * b:GetSizeY() end
			if score > bestScore then best, bestScore = c, score end
		end
	end
	return best
end

---------------------------------------------------------------- battle (NPCs + bots)
local botState = {}

local function spawnSide(side)
	local b = Sigf.Battle
	local pos = Sigf.Ground(Sigf.ArenaPos, b.radius)
	local e
	if side == "combine" then
		e = Sigf.NPC(b.combineClass, pos, { weapon = Sigf.Pick(b.combineWeapons) })
	else
		e = Sigf.NPC("npc_citizen", pos, { weapon = Sigf.Pick(b.rebelWeapons), keys = { citizentype = 3 } })
	end
	if not IsValid(e) then return end
	e.SigfSide = side
	hook.Run("SigfBattleSpawn", e, side)
end

local botN = 0
local function battleTick()
	local b = Sigf.Battle
	if not b.enabled then return end
	local count, list = { combine = 0, rebel = 0 }, { combine = {}, rebel = {} }
	for _, e in ipairs(ents.GetAll()) do
		if e.SigfSide and e:IsNPC() and e:Health() > 0 then
			count[e.SigfSide] = count[e.SigfSide] + 1
			table.insert(list[e.SigfSide], e)
		end
	end
	for _ = 1, math.min(2, b.combine - count.combine) do spawnSide("combine") end
	for _ = 1, math.min(2, b.rebels - count.rebel) do spawnSide("rebel") end
	-- NPCs without an enemy run toward the other side: the battle never stops.
	for side, mine in pairs(list) do
		local other = list[side == "combine" and "rebel" or "combine"]
		for _, e in ipairs(mine) do
			if not IsValid(e:GetEnemy()) then
				local t = Sigf.Pick(other)
				e:SetLastPosition(IsValid(t) and t:GetPos() or Sigf.Ground(Sigf.ArenaPos, b.radius))
				e:SetSchedule(SCHED_FORCED_GO_RUN)
			end
		end
	end
	local bots = player.GetBots()
	if #bots < b.bots and #player.GetAll() < game.MaxPlayers() then
		botN = botN + 1
		player.CreateNextBot("Bot" .. botN)
	end
end

-- Bots: aim at the nearest enemy NPC and shoot, otherwise walk toward a point in the arena.
local function botThink()
	local now = CurTime()
	for _, p in ipairs(player.GetBots()) do
		local s = botState[p] or {}
		botState[p] = s
		if not p:Alive() then
			s.deadAt = s.deadAt or now
			if now - s.deadAt > 3 then s.deadAt = nil p:Spawn() end
		else
			s.deadAt = nil
			local best, bestD = nil, 2000 * 2000
			for _, e in ipairs(Sigf.NPCs()) do
				if e:IsNPC() and e:Disposition(p) == D_HT then
					local d = e:GetPos():DistToSqr(p:GetPos())
					if d < bestD then best, bestD = e, d end
				end
			end
			s.enemy = best
			s.sees = false
			if best then
				local tr = util.TraceLine({ start = p:GetShootPos(), endpos = best:WorldSpaceCenter(), filter = p, mask = MASK_SHOT })
				s.sees = tr.Entity == best or tr.Fraction > 0.97
			end
			if s.lastPos and s.lastPos:DistToSqr(p:GetPos()) < 16 * 16 and s.goal then
				s.jumpUntil = now + 0.3
				s.stuck = (s.stuck or 0) + 1
				if s.stuck > 3 then s.goal = nil s.stuck = 0 end
			else
				s.stuck = 0
			end
			s.lastPos = p:GetPos()
		end
	end
end

function Sigf.BotCommand(p, cmd)
	if p.SigfManual then return end -- the mod drives this bot itself
	cmd:ClearMovement()
	cmd:ClearButtons()
	if not p:Alive() then return end
	local s = botState[p]
	if not s or not Sigf.ArenaPos then return end
	local now = CurTime()
	if not s.goal or now > (s.repick or 0) or p:GetPos():DistToSqr(s.goal) < 100 * 100 then
		s.goal = Sigf.Ground(Sigf.ArenaPos, Sigf.Battle.radius)
		s.repick = now + math.Rand(5, 9)
	end
	local to = s.goal - p:GetPos()
	to.z = 0
	local view
	if IsValid(s.enemy) and s.enemy:Health() > 0 then
		view = (s.enemy:WorldSpaceCenter() - p:GetShootPos()):Angle()
		view.p = math.NormalizeAngle(view.p)
	else
		view = Angle(0, to:Angle().y, 0)
	end
	cmd:SetViewAngles(view)
	if to:Length() > 60 then
		local d = math.rad(math.AngleDifference(to:Angle().y, view.y))
		cmd:SetForwardMove(math.cos(d) * 250)
		cmd:SetSideMove(-math.sin(d) * 250)
	end
	local b = 0
	if s.sees then b = bit.bor(b, IN_ATTACK) end
	if s.jumpUntil and now < s.jumpUntil then b = bit.bor(b, IN_JUMP) end
	cmd:SetButtons(b)
	local w = p:GetWeapon("weapon_smg1")
	if IsValid(w) and p:GetActiveWeapon() ~= w then cmd:SelectWeapon(w) end
end

---------------------------------------------------------------- stream player and camera
local function setupHost(p)
	if stage == "demo" then
		p:GodEnable()
		p:SetNW2Bool("sigf_pilot", true)
		p:Give("weapon_smg1")
		p:GiveAmmo(900, "SMG1", true)
		p:SelectWeapon("weapon_smg1")
		if Sigf.ArenaPos then p:SetPos(Sigf.Ground(Sigf.ArenaPos, 500)) end
		if not Sigf.ShowReady then
			timer.Simple(3, function()
				if Sigf.ShowReady then return end
				Sigf.ShowReady = true
				print("SIGF_SHOWCASE_READY")
			end)
		end
	else
		p:StripWeapons()
		p:GodEnable()
		p:SetNoDraw(true)
		p:SetNotSolid(true)
		p:DrawShadow(false)
		p:SetMoveType(MOVETYPE_NOCLIP)
		p:AddFlags(FL_NOTARGET)
	end
end

hook.Add("PlayerSpawn", "sigf_stage_spawn", function(p)
	timer.Simple(0.2, function()
		if not IsValid(p) then return end
		if p:IsBot() then
			p:Give("weapon_smg1")
			p:GiveAmmo(900, "SMG1", true)
		elseif p:IsListenServerHost() then
			setupHost(p)
		end
	end)
end)

hook.Add("EntityTakeDamage", "sigf_action", function(target, dmg)
	local a = dmg:GetAttacker()
	if IsValid(a) and a ~= target and (a:IsNPC() or a:IsPlayer()) and not Sigf.IsCamera(a) then Sigf.LastAction = a end
end)

hook.Add("SetupPlayerVisibility", "sigf_pvs", function()
	if Sigf.FocusPos then AddOriginToPVS(Sigf.FocusPos) end
	if Sigf.ArenaPos then AddOriginToPVS(Sigf.ArenaPos) end
end)

-- Every 7 s: the last actor who hit someone (otherwise a random NPC). Sigf.Focus takes priority.
local nextSwitch = 0
local function cameraTick()
	local now = CurTime()
	local cur = GetGlobalEntity("sigf_focus")
	if now < focusUntil then
		applyFocus(Sigf.ForcedFocus)
	elseif now > nextSwitch or (Sigf.FocusPos == nil) or (IsValid(cur) and cur:Health() <= 0) then
		nextSwitch = now + 7
		local t = Sigf.LastAction
		if not IsValid(t) or t:Health() <= 0 or Sigf.IsCamera(t) then t = Sigf.Pick(Sigf.NPCs()) or Sigf.Pick(Sigf.Players()) end
		applyFocus(IsValid(t) and t or Sigf.ArenaPos)
		Sigf.LastAction = nil
	elseif IsValid(cur) then
		applyFocus(cur)
	end
	local h = Sigf.Host()
	if IsValid(h) and Sigf.IsCamera(h) and Sigf.FocusPos then h:SetPos(Sigf.FocusPos + Vector(0, 0, 90)) end
end

---------------------------------------------------------------- demo: pilot and script
local pilot = { goal = nil, repick = 0, enemyAt = 0 }
local function pilotTick()
	local h = Sigf.Host()
	if not IsValid(h) or not h:Alive() then return end
	local now = CurTime()
	local fwd, atk, jump, aim = 0, false, false, nil
	local looking = manual.look ~= nil and now < manual.lookUntil
	if looking then aim = targetPos(manual.look) end
	if now < manual.walkUntil then fwd = manual.speed end
	if now < manual.shootUntil then atk = true end
	if now < manual.jumpUntil then jump = true end
	local busy = looking or now < manual.walkUntil or now < manual.shootUntil
	if Sigf.PilotOn and not busy then
		if now > pilot.enemyAt then
			pilot.enemyAt = now + 0.5
			local best, bestD = nil, 2500 * 2500
			for _, e in ipairs(Sigf.NPCs()) do
				if hostile(e, h) then
					local d = e:GetPos():DistToSqr(h:GetPos())
					if d < bestD then best, bestD = e, d end
				end
			end
			pilot.enemy = best
		end
		local e = pilot.enemy
		if hostile(e, h) then
			aim = e:WorldSpaceCenter()
			local d = e:GetPos():Distance(h:GetPos())
			if d > 450 then fwd = 180 end
			local tr = util.TraceLine({ start = h:EyePos(), endpos = aim, filter = h, mask = MASK_SHOT })
			atk = d < 1400 and (tr.Entity == e or tr.Fraction > 0.97)
		else
			if not pilot.goal or now > pilot.repick or h:GetPos():DistToSqr(pilot.goal) < 120 * 120 then
				pilot.goal = Sigf.Ground(Sigf.ArenaPos, 1000)
				pilot.repick = now + 8
			end
			aim = pilot.goal + Vector(0, 0, 60)
			fwd = 160
		end
		if pilot.lastPos and fwd > 0 and pilot.lastPos:DistToSqr(h:GetPos()) < 4 then jump = true pilot.goal = nil end
		pilot.lastPos = h:GetPos()
	end
	if aim then
		local want = (aim - h:EyePos()):Angle()
		local cur = h:EyeAngles()
		local k = looking and 1 or 0.35
		local new = Angle(cur.p + math.AngleDifference(want.p, cur.p) * k, cur.y + math.AngleDifference(want.y, cur.y) * k, 0)
		h:SetEyeAngles(new)
		h:SetNW2Angle("sigf_aim", new)
	end
	h:SetNW2Bool("sigf_aimon", aim ~= nil)
	h:SetNW2Float("sigf_fwd", fwd)
	h:SetNW2Bool("sigf_atk", atk)
	h:SetNW2Bool("sigf_jump", jump)
	if h:GetAmmoCount("SMG1") < 200 then h:GiveAmmo(600, "SMG1", true) end
end

local function demoTick()
	if not Sigf.ShowReady then return end
	local now = CurTime()
	if not Sigf.RecAt and readData("rec.txt") == "1" then
		Sigf.RecAt = now
		print("SIGF_DEMO_START")
	end
	if not Sigf.RecAt then return end
	for _, s in ipairs(Sigf.Steps) do
		if not s.done and now >= Sigf.RecAt + s.sec then
			s.done = true
			Sigf.Safe("demo step " .. s.sec, s.fn)
		end
	end
end

---------------------------------------------------------------- stage clocks
local function every(name, sec, fn)
	timer.Create(name, sec, 0, function()
		local ok, e = xpcall(fn, debug.traceback)
		if not ok then Sigf.Report(name, e) end
	end)
end

hook.Add("InitPostEntity", "sigf_stage", function()
	SetGlobalString("sigf_stage", stage)
	timer.Simple(1, function()
		Sigf.ArenaPos = computeArena()
		SetGlobalVector("sigf_arena", Sigf.ArenaPos)
		applyFocus(Sigf.ArenaPos)
		local a = Sigf.ArenaPos
		print("SIGF_ARENA Vector(" .. math.floor(a.x) .. ", " .. math.floor(a.y) .. ", " .. math.floor(a.z) .. ") navmesh=" .. tostring(navmesh.IsLoaded()))
		every("sigf_battle", 3, battleTick)
		every("sigf_bots", 0.5, botThink)
		if stage == "demo" then
			every("sigf_pilot", 0.1, pilotTick)
			every("sigf_demo", 0.1, demoTick)
			local h = Sigf.Host()
			if IsValid(h) and h:Alive() then setupHost(h) end
		else
			every("sigf_camera", 0.5, cameraTick)
		end
	end)
end)
