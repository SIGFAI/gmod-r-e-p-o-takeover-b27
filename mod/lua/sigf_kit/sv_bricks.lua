-- $MOD kit: server bricks (frozen, do not copy into the mod).
-- Timers (count from the moment the stream player is in game):
--   Sigf.Every(sec, fn)          fn() every sec seconds (first time in sec s), returns a name for Sigf.Stop
--   Sigf.After(sec, fn)          fn() once, in sec s
--   Sigf.Stop(name)              stops a timer
-- Places:
--   Sigf.Ground(center, radius)  random ground point (navmesh), optional: within radius of center
--   Sigf.Action()                where the stream camera is looking (otherwise the arena center)
--   Sigf.Arena()                 center of the arena where the kit makes the NPCs fight
-- Entities (from a timer or a hook, not at load time):
--   Sigf.Prop(model, pos, scale, life)         physics object, removed after life s (default 20, 0 = never)
--   Sigf.NPC(class, pos, opts)                 NPC; opts: weapon, model, health, scale, life, keys, yaw
--   Sigf.Sprite(mat, posOrEnt, size, life, opts)  floating image facing the camera (material from texture.py)
--   Sigf.Effect(name, pos, opts)               engine effect ("Explosion", "cball_explode"...)
--   Sigf.Explode(pos, radius, damage, attacker)
--   Sigf.Sound(path, pos, level, pitch)        sound in the world; Sigf.Sound2D(path) for everyone, without position
--   Sigf.Text(text, sec, opts)                 big on-screen text; Sigf.Say(text) in the chat
--   Sigf.Overlay(mat, sec, alpha)              full-screen image; Sigf.Shake(pos, amp, sec, radius)
--   Sigf.Teleport(ent, pos, vel)               vel nil = keeps its velocity
--   Sigf.Model(ent, model, keep)               new model; keep = keep it after respawn (players)
--   Sigf.Scale(ent, s, sec)                    size x s over sec seconds
--   Sigf.Portal(a, b, opts, life) / Sigf.PortalsEvery(sec, life, opts)
--   Sigf.Remove(id)                            removes a sprite or a portal (returned id)
util.AddNetworkString("sigf_msg")
util.AddNetworkString("sigf_hello")

Sigf.StageName = string.Trim(file.Read("sigf/stage.txt", "DATA") or "home")
if Sigf.StageName == "" then Sigf.StageName = "home" end
SetGlobalString("sigf_stage", Sigf.StageName)

local nextId = 0
local function newId() nextId = nextId + 1 return nextId end

---------------------------------------------------------------- errors
local errCount = {}
function Sigf.Report(where, err)
	errCount[where] = (errCount[where] or 0) + 1
	if errCount[where] <= 3 then print("SIGF_ERROR " .. where .. ": " .. tostring(err)) end
end

-- Calls fn(); an error is reported to the check (SIGF_ERROR) instead of breaking the caller.
function Sigf.Safe(where, fn)
	local ok, r = xpcall(fn, debug.traceback)
	if not ok then Sigf.Report(where, r) end
	return ok, r
end

---------------------------------------------------------------- mod loading
local function compiles(path)
	local code = file.Read(path, "LUA")
	if not code then return nil end
	local r = CompileString(code, path, false)
	if isstring(r) then print("SIGF_ERROR syntax: " .. r) return false end
	return true
end

local function run(path)
	local ok, e = xpcall(function() include(path) end, debug.traceback)
	if not ok then print("SIGF_ERROR " .. path .. ": " .. tostring(e)) end
	return ok
end

-- Sigf.ModState: "none" (no mod), "error" (the mod does not compile or crashes on load), "ok".
function Sigf.LoadMod()
	Sigf.ModState = "none"
	if not file.Exists("sigf_mod/sv.lua", "LUA") then return end
	local ok = true
	-- All mod files are compiled here (cl.lua and demo.lua included): a syntax error shows up in the check.
	for _, f in ipairs({ "sh", "sv", "cl", "demo" }) do
		if compiles("sigf_mod/" .. f .. ".lua") == false then ok = false end
	end
	if not ok then Sigf.ModState = "error" return end
	for _, f in ipairs({ "sh", "cl" }) do
		if file.Exists("sigf_mod/" .. f .. ".lua", "LUA") then AddCSLuaFile("sigf_mod/" .. f .. ".lua") end
	end
	if file.Exists("sigf_mod/sh.lua", "LUA") then ok = run("sigf_mod/sh.lua") and ok end
	ok = run("sigf_mod/sv.lua") and ok
	if Sigf.Stage() == "demo" then
		if file.Exists("sigf_mod/demo.lua", "LUA") then ok = run("sigf_mod/demo.lua") and ok else print("SIGF_NODEMO") end
	end
	Sigf.ModState = ok and "ok" or "error"
end

---------------------------------------------------------------- network to clients
function Sigf.Net(kind, data, ply)
	net.Start("sigf_msg")
	net.WriteString(kind)
	net.WriteTable(data or {})
	if ply then net.Send(ply) else net.Broadcast() end
end

-- What stays on screen (sprites, portals) is resent to a joining client (after a map change).
Sigf.Visible = Sigf.Visible or {}
local function keep(id, kind, d)
	local now = CurTime()
	for k, v in pairs(Sigf.Visible) do
		if v.d.die > 0 and v.d.die < now then Sigf.Visible[k] = nil end
	end
	Sigf.Visible[id] = { kind = kind, d = d }
end

---------------------------------------------------------------- timers
Sigf.ReadyAt = nil
local queue = {}

local function startTimer(t)
	timer.Create(t.name, math.max(t.sec, 0.01), t.every and 0 or 1, function()
		local ok, e = xpcall(t.fn, debug.traceback)
		if not ok then Sigf.Report("timer " .. t.name, e) end
	end)
end

local function addTimer(sec, fn, every)
	local t = { name = "sigf_t" .. newId(), sec = sec, fn = fn, every = every }
	if Sigf.ReadyAt then startTimer(t) else queue[#queue + 1] = t end
	return t.name
end

function Sigf.Every(sec, fn) return addTimer(sec, fn, true) end
function Sigf.After(sec, fn) return addTimer(sec, fn, false) end
function Sigf.Stop(name)
	timer.Remove(name)
	for i = #queue, 1, -1 do if queue[i].name == name then table.remove(queue, i) end end
end

-- The stream player is in game (their client has loaded): timers start, the check reads SIGF_READY.
function Sigf.MarkReady()
	if Sigf.ReadyAt then return end
	Sigf.ReadyAt = CurTime()
	for _, t in ipairs(queue) do startTimer(t) end
	queue = {}
	hook.Run("SigfReady")
end

net.Receive("sigf_hello", function(_, ply)
	for id, v in pairs(Sigf.Visible) do
		if v.d.die == 0 or v.d.die > CurTime() then Sigf.Net(v.kind, v.d, ply) end
	end
	Sigf.MarkReady()
end)

-- Server without a player (someone's dedicated server): start anyway.
hook.Add("InitPostEntity", "sigf_ready_fallback", function()
	timer.Simple(Sigf.Stage() == "home" and 20 or 120, function()
		if not Sigf.ReadyAt then
			if Sigf.Stage() ~= "home" then print("SIGF_ERROR the stream client never joined") end
			Sigf.MarkReady()
		end
	end)
end)

---------------------------------------------------------------- places
local navAreas
local function areas()
	if navAreas == nil then
		navAreas = {}
		if navmesh.IsLoaded() then
			for _, a in ipairs(navmesh.GetAllNavAreas()) do
				if not a:IsUnderwater() and a:GetSizeX() >= 32 and a:GetSizeY() >= 32 then navAreas[#navAreas + 1] = a end
			end
		end
	end
	return navAreas
end

-- Ground under (x, y), starting from z + 256; nil if nothing walkable.
local function groundAt(x, y, z)
	local tr = util.TraceLine({ start = Vector(x, y, z + 256), endpos = Vector(x, y, z - 2048), mask = MASK_SOLID_BRUSHONLY })
	if not tr.Hit or tr.StartSolid or tr.HitSky or tr.HitNormal.z < 0.7 then return nil end
	if not util.IsInWorld(tr.HitPos + Vector(0, 0, 40)) then return nil end
	return tr.HitPos
end

local function bases()
	local out = {}
	for _, e in ipairs(ents.FindByClass("info_player_start")) do out[#out + 1] = e:GetPos() end
	for _, e in ipairs(Sigf.Actors()) do out[#out + 1] = e:GetPos() end
	return out
end

function Sigf.Ground(center, radius)
	radius = radius or 1500
	local list = areas()
	if #list > 0 then
		local pool = list
		if center then
			pool = {}
			local r2 = (radius + 200) * (radius + 200)
			for _, a in ipairs(list) do if a:GetCenter():DistToSqr(center) < r2 then pool[#pool + 1] = a end end
			if #pool == 0 then pool = list end
		end
		for _ = 1, 20 do
			local p = pool[math.random(#pool)]:GetRandomPoint()
			if not center or p:DistToSqr(center) <= radius * radius then return p + Vector(0, 0, 2) end
		end
		return pool[math.random(#pool)]:GetRandomPoint() + Vector(0, 0, 2)
	end
	-- No navmesh: a random point around a spawn point or an actor, placed on the ground.
	local b = bases()
	for _ = 1, 40 do
		local base = center or Sigf.Pick(b) or Vector(0, 0, 0)
		local ang = math.Rand(0, math.pi * 2)
		local d = math.Rand(0, center and radius or 800)
		local p = groundAt(base.x + math.cos(ang) * d, base.y + math.sin(ang) * d, base.z)
		if p then return p + Vector(0, 0, 2) end
	end
	return (center or Sigf.Pick(b) or Vector(0, 0, 0)) + Vector(0, 0, 2)
end

function Sigf.Arena() return Sigf.ArenaPos end

function Sigf.Action()
	return Sigf.FocusPos or Sigf.ArenaPos or Sigf.Ground()
end

---------------------------------------------------------------- entities
local function badModel(where, model)
	if not util.IsValidModel(model) then Sigf.Report(where, "unknown model " .. tostring(model)) return true end
	return false
end

function Sigf.Prop(model, pos, scale, life)
	if badModel("Prop", model) then return nil end
	local e = ents.Create("prop_physics")
	if not IsValid(e) then return nil end
	e:SetModel(model)
	e:SetPos(pos)
	e:SetAngles(Angle(0, math.random(0, 359), 0))
	e:Spawn()
	e:Activate()
	-- Model without physics: static object instead.
	if not IsValid(e:GetPhysicsObject()) then
		e:Remove()
		e = ents.Create("prop_dynamic")
		e:SetModel(model)
		e:SetPos(pos)
		e:Spawn()
	end
	if scale and scale ~= 1 then e:SetModelScale(scale, 0) end
	life = life or 20
	if life > 0 then SafeRemoveEntityDelayed(e, life) end
	return e
end

-- class: class ("npc_combine_s") or name from the Sandbox menu list ("Rebel", "CombineElite"...).
function Sigf.NPC(class, pos, opts)
	opts = opts or {}
	local def = list.Get("NPC")[class]
	local cls = def and def.Class or class
	local e = ents.Create(cls)
	if not IsValid(e) then Sigf.Report("NPC", "unknown class " .. tostring(class)) return nil end
	e:SetPos(pos + Vector(0, 0, (def and def.Offset) or 4))
	e:SetAngles(Angle(0, opts.yaw or math.random(0, 359), 0))
	if def then
		for k, v in pairs(def.KeyValues or {}) do e:SetKeyValue(k, tostring(v)) end
		if def.SpawnFlags then e:SetKeyValue("spawnflags", tostring(def.SpawnFlags)) end
		if def.Model then e:SetModel(def.Model) end
	end
	local weapon = opts.weapon or (def and def.Weapons and def.Weapons[1])
	if weapon and weapon ~= "" then e:SetKeyValue("additionalequipment", weapon) end
	for k, v in pairs(opts.keys or {}) do e:SetKeyValue(k, tostring(v)) end
	e:Spawn()
	e:Activate()
	if opts.model and not badModel("NPC", opts.model) then e:SetModel(opts.model) end
	if opts.health then e:SetMaxHealth(opts.health) e:SetHealth(opts.health) end
	if opts.scale then e:SetModelScale(opts.scale, 0) end
	if opts.life and opts.life > 0 then SafeRemoveEntityDelayed(e, opts.life) end
	return e
end

-- size: height in world units (a player is 72 tall). where: position or entity (the image floats above it).
-- opts: color (Color), offset (Vector, relative to the entity).
function Sigf.Sprite(mat, where, size, life, opts)
	opts = opts or {}
	local id = newId()
	life = life or 10
	local d = { id = id, mat = mat, size = size or 48, die = life > 0 and CurTime() + life or 0, color = opts.color, off = opts.offset }
	if isentity(where) then d.ent = where:EntIndex() else d.pos = where end
	keep(id, "sprite", d)
	Sigf.Net("sprite", d)
	return id
end

function Sigf.Remove(id)
	Sigf.Visible[id] = nil
	if Sigf.Portals then Sigf.Portals[id] = nil end
	Sigf.Net("remove", { id = id })
end

-- opts: scale, magnitude, radius, normal, start, ent, color (number). List: NOTES.md.
function Sigf.Effect(name, pos, opts)
	opts = opts or {}
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetStart(opts.start or pos)
	ed:SetNormal(opts.normal or Vector(0, 0, 1))
	ed:SetScale(opts.scale or 1)
	ed:SetMagnitude(opts.magnitude or 1)
	ed:SetRadius(opts.radius or 64)
	if opts.color then ed:SetColor(opts.color) end
	if IsValid(opts.ent) then ed:SetEntity(opts.ent) end
	util.Effect(name, ed, true, true)
end

function Sigf.Explode(pos, radius, damage, attacker)
	Sigf.Effect("Explosion", pos, { magnitude = 1, scale = 1 })
	local a = IsValid(attacker) and attacker or game.GetWorld()
	util.BlastDamage(a, a, pos, radius or 200, damage or 60)
end

function Sigf.Sound(path, pos, level, pitch)
	sound.Play(path, pos, level or 90, pitch or 100, 1)
end

function Sigf.Sound2D(path) Sigf.Net("sound", { path = path }) end

-- opts: color (Color), y (0 = top, 1 = bottom, default 0.22), size (font size, default 64).
function Sigf.Text(text, sec, opts)
	opts = opts or {}
	Sigf.Net("text", { text = tostring(text), sec = sec or 4, color = opts.color, y = opts.y, size = opts.size })
end
Sigf.Caption = Sigf.Text

function Sigf.Say(text) PrintMessage(HUD_PRINTTALK, tostring(text)) end

function Sigf.Overlay(mat, sec, alpha)
	Sigf.Net("overlay", { mat = mat, sec = sec or 2, alpha = alpha or 255 })
end

function Sigf.Shake(pos, amp, sec, radius)
	util.ScreenShake(pos, amp or 8, 20, sec or 1, radius or 3000)
end

-- Current velocity (physics objects included).
function Sigf.Velocity(ent)
	if not ent:IsPlayer() and not ent:IsNPC() and ent:GetMoveType() == MOVETYPE_VPHYSICS then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then return phys:GetVelocity() end
	end
	return ent:GetVelocity()
end

function Sigf.Teleport(ent, pos, vel)
	if not IsValid(ent) then return end
	local old = Sigf.Velocity(ent)
	ent:SetPos(pos)
	if vel == nil then return end
	if ent:IsPlayer() then
		ent:SetVelocity(vel - ent:GetVelocity()) -- on a player, SetVelocity adds
	elseif ent:GetMoveType() == MOVETYPE_VPHYSICS then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity(vel) phys:Wake() end
	elseif ent:IsNPC() then
		ent:SetLocalVelocity(vel)
	else
		ent:SetVelocity(vel)
		if vel:LengthSqr() > 1 then ent:SetAngles(vel:Angle()) end
	end
end

-- Players: "models/player/*.mdl" models keep all animations. NPCs: a model with another skeleton
-- may stay frozen. keep = true: the player keeps it after each respawn.
function Sigf.Model(ent, model, keep)
	if not IsValid(ent) or badModel("Model", model) then return end
	ent:SetModel(model)
	if keep and ent:IsPlayer() then ent.SigfModel = model end
end

hook.Add("PlayerSetModel", "sigf_model", function(p)
	if p.SigfModel then p:SetModel(p.SigfModel) return true end
end)

function Sigf.Scale(ent, s, sec)
	if not IsValid(ent) then return end
	ent:SetModelScale(s, sec or 0.3)
	if ent:IsPlayer() then
		ent:SetViewOffset(Vector(0, 0, 64 * s))
		ent:SetViewOffsetDucked(Vector(0, 0, 28 * s))
		ent:SetStepSize(18 * math.max(s, 1))
	end
end

---------------------------------------------------------------- portals
Sigf.Portals = Sigf.Portals or {}
local PROJECTILES = {
	rpg_missile = true, crossbow_bolt = true, npc_grenade_frag = true, prop_combine_ball = true,
	grenade_ar2 = true, npc_satchel = true, grenade_helicopter = true,
}
local cool = setmetatable({}, { __mode = "k" })

local function canPass(o, e)
	if e:IsPlayer() then return o.players and e:Alive() and not Sigf.IsCamera(e) end
	if e:IsNPC() or e:IsNextBot() then return o.npcs and e:Health() > 0 end
	if not o.props then return false end
	local c = e:GetClass()
	return c == "prop_physics" or c == "prop_physics_multiplayer" or PROJECTILES[c] == true
end

local function pass(o, e, from, to)
	local now = CurTime()
	if (cool[e] or 0) > now then return end
	cool[e] = now + o.cooldown
	Sigf.Teleport(e, to + Vector(0, 0, e:IsPlayer() and 8 or 24), Sigf.Velocity(e) * o.boost)
	Sigf.Effect("cball_explode", from + Vector(0, 0, 32))
	Sigf.Effect("cball_explode", to + Vector(0, 0, 32))
	Sigf.Sound("ambient/machines/teleport1.wav", from, 75)
	Sigf.Sound("ambient/machines/teleport3.wav", to, 75)
	if o.onEnter then Sigf.Safe("portal onEnter", function() o.onEnter(e, from, to) end) end
end

local function portalTick()
	local now = CurTime()
	for id, o in pairs(Sigf.Portals) do
		if o.die > 0 and o.die < now then
			Sigf.Portals[id] = nil
		else
			for _, side in ipairs(o.oneway and { { o.a, o.b } } or { { o.a, o.b }, { o.b, o.a } }) do
				for _, e in ipairs(ents.FindInSphere(side[1] + Vector(0, 0, 24), o.radius)) do
					if canPass(o, e) then pass(o, e, side[1], side[2]) end
				end
			end
		end
	end
end

-- Two linked portals: a (orange) and b (blue). What enters one comes out of the other keeping its velocity.
-- opts (all optional): radius 60, cooldown 1.5, oneway false, boost 1, players true, npcs true,
--   props true (physics objects and projectiles), colorA, colorB (Color), sprite ("sigf/x"), spriteSize 48,
--   onEnter function(ent, from, to)
function Sigf.Portal(a, b, opts, life)
	local o = { radius = 60, cooldown = 1.5, oneway = false, boost = 1, players = true, npcs = true, props = true,
		colorA = Color(255, 140, 0), colorB = Color(0, 150, 255), spriteSize = 48 }
	for k, v in pairs(opts or {}) do o[k] = v end
	o.id = newId()
	o.a = a
	o.b = b
	o.die = (life and life > 0) and CurTime() + life or 0
	Sigf.Portals[o.id] = o
	local d = { id = o.id, a = a, b = b, die = o.die, r = o.radius, sprite = o.sprite, size = o.spriteSize,
		ca = { r = o.colorA.r, g = o.colorA.g, b = o.colorA.b }, cb = { r = o.colorB.r, g = o.colorB.g, b = o.colorB.b } }
	keep(o.id, "portal", d)
	Sigf.Net("portal", d)
	if not timer.Exists("sigf_portals") then
		timer.Create("sigf_portals", 0.1, 0, function()
			local ok, e = xpcall(portalTick, debug.traceback)
			if not ok then Sigf.Report("portals", e) end
		end)
	end
	return o
end

-- A new pair every sec s, each lives life s. opts: like Sigf.Portal, plus center and within
-- (area, default: the arena, 1500 units) and minDist (gap between the two, default 500).
function Sigf.PortalsEvery(sec, life, opts)
	opts = opts or {}
	return Sigf.Every(sec, function()
		local c = opts.center or Sigf.Arena()
		local w = opts.within or 1500
		local a = Sigf.Ground(c, w)
		local b = Sigf.Ground(c, w)
		for _ = 1, 6 do
			if a:Distance(b) >= (opts.minDist or 500) then break end
			b = Sigf.Ground(c, w)
		end
		Sigf.Portal(a, b, opts, life or 20)
	end)
end
