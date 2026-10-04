-- R.E.P.O. Takeover, client: loot labels and glow, extraction zone, money HUD, popups, moody look.
local coin = Material("sigf/dollar")
local glowMat = Material("sprites/light_glow02_add")
local beamMat = Material("effects/laser1")

local function f(name, size, weight)
	surface.CreateFont(name, { font = "Roboto", size = math.floor(size * ScrH() / 1080), weight = weight or 900, antialias = true })
end
f("RepoBig", 66) f("RepoMid", 34) f("RepoSmall", 26) f("RepoTag", 30)

local function money(n) return "$" .. string.Comma(math.floor(n)) end

---------------------------------------------------------------- tracked entities
local loot, tagged = {}, {}
timer.Create("repo_scan", 0.4, 0, function()
	loot, tagged = {}, {}
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) then
			if e:GetNWInt("repo_max", 0) > 0 then loot[#loot + 1] = e
			elseif e:GetNWString("repo_tag", "") ~= "" then tagged[#tagged + 1] = e end
		end
	end
end)

hook.Add("PreDrawHalos", "repo_halos", function()
	local good, hurt = {}, {}
	for _, e in ipairs(loot) do
		if IsValid(e) and e:GetPos():DistToSqr(EyePos()) < 1800 ^ 2 then
			local r = e:GetNWInt("repo_value") / math.max(1, e:GetNWInt("repo_max"))
			table.insert(r > 0.65 and good or hurt, e)
		end
	end
	local pulse = 2 + math.sin(CurTime() * 4)
	if #good > 0 then halo.Add(good, Color(255, 215, 60), pulse, pulse, 2, true, true) end
	if #hurt > 0 then halo.Add(hurt, Color(255, 110, 40), pulse, pulse, 2, true, true) end
end)

---------------------------------------------------------------- world drawing
local function label(pos, lines)
	local ang = EyeAngles()
	ang:RotateAroundAxis(ang:Right(), 90)
	ang:RotateAroundAxis(ang:Up(), -90)
	local d = pos:Distance(EyePos())
	local s = math.Clamp(d, 200, 900) * 0.0012
	cam.Start3D2D(pos, ang, s)
	local y = 0
	for i = #lines, 1, -1 do
		local l = lines[i]
		draw.SimpleTextOutlined(l.text, l.font, 0, y, l.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 3, Color(0, 0, 0, 230))
		y = y - 40
	end
	cam.End3D2D()
end

hook.Add("PostDrawTranslucentRenderables", "repo_world", function(depth, sky)
	if depth or sky then return end
	local eye = EyePos()
	-- only the nearest few loot labels, so they never pile up
	local near = {}
	for _, e in ipairs(loot) do
		if IsValid(e) and not e:IsDormant() then
			local d2 = e:GetPos():DistToSqr(eye)
			if d2 < 1400 ^ 2 then near[#near + 1] = { e = e, d = d2 } end
		end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	for i, n in ipairs(near) do
		local e = n.e
		local v, m = e:GetNWInt("repo_value"), e:GetNWInt("repo_max")
		local r = v / math.max(1, m)
		local c = r > 0.65 and Color(255, 230, 80) or (r > 0.3 and Color(255, 150, 50) or Color(255, 70, 50))
		render.SetMaterial(glowMat)
		render.DrawSprite(e:WorldSpaceCenter(), 120, 120, Color(255, 200, 40, 120))
		-- spinning-looking coin floats over every piece of loot
		render.SetMaterial(coin)
		render.DrawSprite(e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 16 + math.sin(CurTime() * 3 + i) * 3), 22, 22, color_white)
		if i <= 3 then
			label(e:GetPos() + Vector(0, 0, e:OBBMaxs().z + 34), {
				{ text = money(v), font = "RepoBig", color = c },
				{ text = e:GetNWString("repo_name"), font = "RepoSmall", color = Color(255, 255, 255) },
			})
		end
	end
	local lit = 0
	for _, e in ipairs(loot) do
		if IsValid(e) and lit < 12 and e:GetPos():DistToSqr(eye) < 1100 ^ 2 then
			lit = lit + 1
			local dl = DynamicLight(e:EntIndex())
			if dl then
				dl.pos = e:WorldSpaceCenter() dl.r = 255 dl.g = 200 dl.b = 60
				dl.brightness = 2 dl.decay = 1000 dl.size = 200 dl.dietime = CurTime() + 0.2
			end
		end
	end
	local gl = 0
	for _, e in ipairs(tagged) do
		if IsValid(e) and gl < 6 and e:GetPos():DistToSqr(eye) < 1200 ^ 2 then
			gl = gl + 1
			local dl = DynamicLight(e:EntIndex() + 1000)
			if dl then
				local huge = e:GetNWString("repo_tag") == "HUNTSMAN"
				dl.pos = e:WorldSpaceCenter() dl.r = huge and 255 or 90 dl.g = huge and 40 or 255 dl.b = huge and 40 or 60
				dl.brightness = 3 dl.decay = 1000 dl.size = huge and 260 or 150 dl.dietime = CurTime() + 0.2
			end
		end
	end
	local tn = {}
	for _, e in ipairs(tagged) do
		if IsValid(e) and not e:IsDormant() then
			local d2 = e:GetPos():DistToSqr(eye)
			if d2 < 1200 ^ 2 then tn[#tn + 1] = { e = e, d = d2 } end
		end
	end
	table.sort(tn, function(a, b) return a.d < b.d end)
	for i = 1, math.min(3, #tn) do
		local e = tn[i].e
		local huge = e:GetNWString("repo_tag") == "HUNTSMAN"
		label(e:GetPos() + Vector(0, 0, e:OBBMaxs().z * (huge and 1.3 or 1.1) + 14), {
			{ text = e:GetNWString("repo_tag"), font = huge and "RepoBig" or "RepoTag", color = Color(255, 70, 70) },
		})
	end

	-- extraction zone: ring, pillar of light, sign
	local z = GetGlobalVector("repo_zone", vector_origin)
	if z ~= vector_origin then
		local t = CurTime()
		local R = 120
		local pulse = 0.6 + 0.4 * math.sin(t * 3)
		render.SetMaterial(glowMat)
		render.DrawQuadEasy(z + Vector(0, 0, 3), Vector(0, 0, 1), R * 3.4, R * 3.4, Color(60, 255, 90, 120 * pulse), 0)
		render.SetMaterial(beamMat)
		render.DrawBeam(z, z + Vector(0, 0, 520), 70 + 12 * pulse, 0, 1, Color(80, 255, 110, 140))
		render.DrawBeam(z, z + Vector(0, 0, 520), 26, 0, 1, Color(220, 255, 230, 220))
		local seg = 36
		for i = 0, seg - 1 do
			local a1, a2 = i / seg * math.pi * 2 + t, (i + 1) / seg * math.pi * 2 + t
			local p1 = z + Vector(math.cos(a1), math.sin(a1), 0) * R + Vector(0, 0, 6)
			local p2 = z + Vector(math.cos(a2), math.sin(a2), 0) * R + Vector(0, 0, 6)
			render.DrawBeam(p1, p2, 9, 0, 1, Color(120, 255, 140, 255))
		end
		label(z + Vector(0, 0, 300 + 8 * math.sin(t * 2)), {
			{ text = "EXTRACTION POINT", font = "RepoMid", color = Color(120, 255, 140) },
			{ text = "drop the loot here", font = "RepoSmall", color = Color(255, 255, 255) },
		})
	end
end)

---------------------------------------------------------------- popups and HUD
local pops = {}
net.Receive("repo_pop", function()
	local pos, text, kind = net.ReadVector(), net.ReadString(), net.ReadUInt(3)
	pops[#pops + 1] = { pos = pos, text = text, kind = kind, t = RealTime(), dx = math.Rand(-60, 60), dy = math.Rand(-30, 30) }
	while #pops > 24 do table.remove(pops, 1) end
end)

local cheerAt = 0
net.Receive("repo_cheer", function() cheerAt = RealTime() surface.PlaySound("garrysmod/save_load1.wav") end)

local shown = 0
hook.Add("HUDPaint", "repo_hud", function()
	local now = RealTime()
	local sw, sh = ScrW(), ScrH()
	for i = #pops, 1, -1 do
		local p = pops[i]
		local age = now - p.t
		if age > 1.8 then table.remove(pops, i) else
			local s = (p.pos + Vector(0, 0, age * 40)):ToScreen()
			if s.visible then
				local a = 255 * math.Clamp((1.8 - age) / 0.5, 0, 1)
				local col = p.kind == 0 and Color(255, 70, 60, a) or (p.kind == 1 and Color(110, 255, 120, a) or Color(255, 235, 120, a))
				local big = p.kind <= 1 and "RepoBig" or "RepoMid"
				draw.SimpleTextOutlined(p.text, big, s.x + p.dx, s.y + p.dy - age * 50, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(0, 0, 0, a))
				if p.kind == 1 then
					surface.SetMaterial(coin)
					surface.SetDrawColor(255, 255, 255, a)
					local cs = sh * 0.07
					surface.DrawTexturedRect(s.x + p.dx - cs / 2, s.y - age * 50 - cs - 24, cs, cs)
				end
			end
		end
	end

	-- top bar
	local haul, quota, level = GetGlobalInt("repo_haul", 0), math.max(1, GetGlobalInt("repo_quota", 1)), GetGlobalInt("repo_level", 1)
	shown = Lerp(math.Clamp(FrameTime() * 5, 0, 1), shown, haul)
	local w, h = sw * 0.32, sh * 0.034
	local x, y = (sw - w) / 2, sh * 0.03
	surface.SetDrawColor(0, 0, 0, 190)
	surface.DrawRect(x - 6, y - 6, w + 12, h + 12)
	surface.SetDrawColor(50, 50, 50, 255)
	surface.DrawRect(x, y, w, h)
	local frac = math.Clamp(shown / quota, 0, 1)
	local flash = (now - cheerAt < 2) and (math.sin(now * 20) > 0)
	surface.SetDrawColor(flash and 255 or 90, 255, flash and 255 or 110, 255)
	surface.DrawRect(x, y, w * frac, h)
	draw.SimpleTextOutlined(money(shown) .. " / " .. money(quota), "RepoMid", sw / 2, y + h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0))
	draw.SimpleTextOutlined("LEVEL " .. level .. "  EXTRACTION QUOTA", "RepoSmall", sw / 2, y + h + 22, Color(255, 215, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0))
end)

hook.Add("HUDPaintBackground", "repo_vignette", function()
	local sw, sh = ScrW(), ScrH()
	surface.SetDrawColor(0, 0, 0, 90)
	surface.DrawRect(0, 0, sw, sh * 0.04)
	surface.DrawRect(0, sh * 0.96, sw, sh * 0.04)
end)
