-- $MOD kit: stream stage, client side (frozen). Stream camera and hidden HUD.
--   idle / mod : camera slowly circling the action (target chosen by the server, "sigf_focus").
--   demo       : third-person view behind the player.
local function onStage()
	local st = Sigf.Stage()
	return st == "idle" or st == "mod" or st == "demo"
end

-- HL2 HUD hidden (the stream frame gives the info). The kit's texts go through HUDPaint (CHudGMod).
local HIDE = {
	CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true, CHudCrosshair = true,
	CHudWeaponSelection = true, CHudDamageIndicator = true, CHudZoom = true, CHudPoisonDamageIndicator = true,
	CHudSquadStatus = true, CHudSuitPower = true, CHudGeiger = true, CHudHintDisplay = true, CHudDeathNotice = true,
	CHudHistoryResource = true, CHudQuickInfo = true, CHudTrain = true, CHudVehicle = true, CHudWeapon = true,
	CHudLocator = true,
}
hook.Add("HUDShouldDraw", "sigf_stage_hud", function(name)
	if HIDE[name] and onStage() then return false end
end)
hook.Add("HUDDrawTargetID", "sigf_stage_hud", function() if onStage() then return false end end)
hook.Add("DrawDeathNotice", "sigf_stage_hud", function() if onStage() then return false end end)
hook.Add("PreDrawViewModel", "sigf_stage_vm", function() if onStage() then return true end end)
hook.Add("ShouldDrawLocalPlayer", "sigf_stage_tp", function() if Sigf.Stage() == "demo" then return true end end)

local smooth, yaw = nil, 0
local function clearPath(from, to)
	local tr = util.TraceHull({ start = from, endpos = to, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8), mask = MASK_SOLID_BRUSHONLY })
	return tr.HitPos
end

hook.Add("CalcView", "sigf_stage_cam", function(ply, origin, angles, fov)
	local st = Sigf.Stage()
	if st == "demo" then
		local eye = ply:EyePos()
		local want = eye - angles:Forward() * 120 + angles:Right() * 28 + Vector(0, 0, 12)
		return { origin = clearPath(eye, want), angles = angles, fov = 80, drawviewer = true }
	end
	if st ~= "idle" and st ~= "mod" then return end
	local ent = GetGlobalEntity("sigf_focus")
	local target = IsValid(ent) and ent:WorldSpaceCenter() or GetGlobalVector("sigf_focus_pos", origin)
	-- Switch to a distant target: hard cut; otherwise the camera glides.
	if not smooth or smooth:DistToSqr(target) > 1500 * 1500 then smooth = target end
	smooth = LerpVector(math.Clamp(FrameTime() * 2.5, 0, 1), smooth, target)
	yaw = (yaw + FrameTime() * 9) % 360
	local dir = Angle(18, yaw, 0):Forward()
	local center = smooth + Vector(0, 0, 24)
	local cam = clearPath(center, center - dir * 300 + Vector(0, 0, 90))
	return { origin = cam, angles = (center - cam):Angle(), fov = 75, drawviewer = false }
end)
