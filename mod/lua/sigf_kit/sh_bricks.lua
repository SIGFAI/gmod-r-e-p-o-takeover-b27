-- $MOD kit: shared bricks (server + client). Frozen, do not copy into the mod.
Sigf = Sigf or {}

-- Stage: "home" (mod installed by a player), "idle" (game without mod during the build), "mod" (check),
-- "demo" (recorded demo), "setup" (one-time install). The server reads it from data/sigf/stage.txt.
function Sigf.Stage()
	if SERVER then return Sigf.StageName or "home" end
	return GetGlobalString("sigf_stage", "home")
end

function Sigf.IsDemo() return Sigf.Stage() == "demo" end

-- The stream player outside the demo: an invisible camera (not a target, not a player, no portals).
function Sigf.IsCamera(p)
	if not IsValid(p) or not p:IsPlayer() then return false end
	local st = Sigf.Stage()
	return (st == "idle" or st == "mod") and p:IsListenServerHost()
end

-- The stream player (host of the local server), or nil.
function Sigf.Host()
	for _, p in ipairs(player.GetHumans()) do
		if p:IsListenServerHost() then return p end
	end
	return player.GetHumans()[1]
end

-- Living players (bots included; the stream player only during the demo).
function Sigf.Players()
	local out = {}
	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and not Sigf.IsCamera(p) then out[#out + 1] = p end
	end
	return out
end

-- Living NPCs (HL2 NPCs and nextbots).
function Sigf.NPCs()
	local out = {}
	for _, e in ipairs(ents.GetAll()) do
		if (e:IsNPC() or e:IsNextBot()) and e:Health() > 0 then out[#out + 1] = e end
	end
	return out
end

-- Everything that moves and fights: living players + living NPCs.
function Sigf.Actors()
	local out = Sigf.Players()
	for _, e in ipairs(Sigf.NPCs()) do out[#out + 1] = e end
	return out
end

-- Actors (living players, NPCs) within r units of pos; filter(ent) optional.
function Sigf.Near(pos, r, filter)
	local out = {}
	for _, e in ipairs(ents.FindInSphere(pos, r)) do
		local ok = (e:IsPlayer() and e:Alive() and not Sigf.IsCamera(e)) or ((e:IsNPC() or e:IsNextBot()) and e:Health() > 0)
		if ok and (not filter or filter(e)) then out[#out + 1] = e end
	end
	return out
end

-- Random pick from a table (nil if empty).
function Sigf.Pick(t)
	if not t or #t == 0 then return nil end
	return t[math.random(#t)]
end
