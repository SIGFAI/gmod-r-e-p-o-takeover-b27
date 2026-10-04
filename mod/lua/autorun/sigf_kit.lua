-- $MOD kit: loader (frozen). Loads the kit's bricks, the guest library if the mod opted into one, then the agent's mod.
-- Order: sh.lua (shared), sv.lua (server), cl.lua (client), demo.lua (server, demo only).
-- Guest library (use-guest.ps1 -> mod/guest.txt; check.ps1 copies it into lua/sigf_guest/): its sh_*.lua, then
-- sv_*.lua (server) or cl_*.lua (client). Without that folder nothing changes.
-- Outside the stream (the mod installed by a player), data/sigf/stage.txt does not exist: only the bricks and the mod run.
Sigf = Sigf or {}

local function guest(prefix)
	local files = file.Find("sigf_guest/" .. prefix .. "_*.lua", "LUA") or {}
	table.sort(files)
	for _, f in ipairs(files) do
		local path = "sigf_guest/" .. f
		if SERVER and prefix ~= "sv" then AddCSLuaFile(path) end
		if (SERVER and prefix ~= "cl") or (CLIENT and prefix ~= "sv") then
			local ok, e = xpcall(function() include(path) end, debug.traceback)
			if not ok then print("SIGF_ERROR " .. path .. ": " .. tostring(e)) end
		end
	end
end

if SERVER then
	for _, f in ipairs({ "sh_bricks", "cl_bricks", "sh_stage", "cl_stage" }) do AddCSLuaFile("sigf_kit/" .. f .. ".lua") end
	include("sigf_kit/sh_bricks.lua")
	include("sigf_kit/sv_bricks.lua")
	include("sigf_kit/sh_stage.lua")
	include("sigf_kit/sv_stage.lua")
	guest("sh") guest("sv") guest("cl")
	Sigf.LoadMod()
else
	include("sigf_kit/sh_bricks.lua")
	include("sigf_kit/cl_bricks.lua")
	include("sigf_kit/sh_stage.lua")
	include("sigf_kit/cl_stage.lua")
	guest("sh") guest("cl")
	Sigf.LoadModClient()
end
