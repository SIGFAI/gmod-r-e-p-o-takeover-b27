-- $MOD kit: stream stage, shared part (frozen). Commands for the demo player (pilot) and the bots.
-- The server decides (NW2 variables on the player), this hook applies them server side and client side (prediction).
hook.Add("StartCommand", "sigf_pilot", function(ply, cmd)
	if SERVER and ply:IsBot() then
		if Sigf.BotCommand then Sigf.BotCommand(ply, cmd) end
		return
	end
	if Sigf.Stage() ~= "demo" or not ply:GetNW2Bool("sigf_pilot", false) then return end
	local fwd = ply:GetNW2Float("sigf_fwd", 0)
	if fwd ~= 0 then cmd:SetForwardMove(fwd) end
	local side = ply:GetNW2Float("sigf_side", 0)
	if side ~= 0 then cmd:SetSideMove(side) end
	local b = cmd:GetButtons()
	if ply:GetNW2Bool("sigf_atk", false) then b = bit.bor(b, IN_ATTACK) end
	if ply:GetNW2Bool("sigf_jump", false) then b = bit.bor(b, IN_JUMP) end
	cmd:SetButtons(b)
	if ply:GetNW2Bool("sigf_aimon", false) then cmd:SetViewAngles(ply:GetNW2Angle("sigf_aim", cmd:GetViewAngles())) end
end)
