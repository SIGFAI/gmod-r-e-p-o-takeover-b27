-- $MOD kit: client side of the bricks (frozen). Receives the server's orders (net "sigf_msg") and draws:
-- texts, full-screen images, sprites in the world, portals, positionless sounds.
local texts, sprites, portals = {}, {}, {}
local overlay
local mats = {}

local function mat(name)
	if not mats[name] then mats[name] = Material(name) end
	return mats[name]
end

local fonts = {}
local function font(size)
	size = math.floor(size or 64)
	if not fonts[size] then
		local name = "SigfText" .. size
		surface.CreateFont(name, { font = "Roboto", size = math.floor(size * ScrH() / 1080), weight = 900, antialias = true })
		fonts[size] = name
	end
	return fonts[size]
end

local function col(c, fallback)
	if not c then return fallback end
	return Color(c.r or 255, c.g or 255, c.b or 255, c.a or 255)
end

local handlers = {
	text = function(d)
		texts[#texts + 1] = { text = d.text, die = RealTime() + (d.sec or 4), start = RealTime(), color = col(d.color, Color(255, 230, 60)), y = d.y, size = d.size }
		while #texts > 4 do table.remove(texts, 1) end
	end,
	overlay = function(d) overlay = { mat = d.mat, die = RealTime() + d.sec, sec = d.sec, alpha = d.alpha } end,
	sound = function(d) surface.PlaySound(d.path) end,
	sprite = function(d) sprites[d.id] = d end,
	portal = function(d) portals[d.id] = d end,
	remove = function(d) sprites[d.id] = nil portals[d.id] = nil end,
}

net.Receive("sigf_msg", function()
	local kind = net.ReadString()
	local d = net.ReadTable()
	local h = handlers[kind]
	if h then
		local ok, e = pcall(h, d)
		if not ok then print("SIGF_ERROR client " .. kind .. ": " .. tostring(e)) end
	end
end)

-- Texts and full-screen image.
hook.Add("HUDPaint", "sigf_hud", function()
	local now = RealTime()
	if overlay then
		if now > overlay.die then overlay = nil else
			local left = overlay.die - now
			local a = overlay.alpha * math.Clamp(left / 0.4, 0, 1) * math.Clamp((overlay.sec - left) / 0.15, 0, 1)
			surface.SetDrawColor(255, 255, 255, a)
			surface.SetMaterial(mat(overlay.mat))
			surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
		end
	end
	local y = 0
	for i = #texts, 1, -1 do
		local t = texts[i]
		if now > t.die then table.remove(texts, i) end
	end
	for _, t in ipairs(texts) do
		local a = 255 * math.Clamp((t.die - now) / 0.4, 0, 1) * math.Clamp((now - t.start) / 0.1, 0, 1)
		local c = Color(t.color.r, t.color.g, t.color.b, a)
		local f = font(t.size)
		local base = (t.y or 0.22) * ScrH()
		draw.SimpleTextOutlined(t.text, f, ScrW() / 2, base + y, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(0, 0, 0, a))
		y = y + (t.size or 64) * ScrH() / 1080 * 1.15
	end
end)

-- Sprites (always facing the camera) and portals (glowing ring facing the camera).
local glow = "sprites/light_glow02_add"
local function drawPortalEnd(pos, c, r, now, d)
	local center = pos + Vector(0, 0, r + 12)
	local ang = EyeAngles()
	local right, up = ang:Right(), ang:Up()
	render.SetMaterial(mat(glow))
	local pulse = 1 + 0.15 * math.sin(now * 6)
	render.DrawSprite(center, r * 2.2 * pulse, r * 2.2 * pulse, Color(c.r, c.g, c.b, 90))
	for i = 0, 15 do
		local t = i / 16 * math.pi * 2 + now * 1.5
		local p = center + (right * math.cos(t) + up * math.sin(t)) * r
		render.DrawSprite(p, 22, 22, Color(c.r, c.g, c.b, 255))
	end
	if d.sprite then
		render.SetMaterial(mat(d.sprite))
		render.DrawSprite(center + Vector(0, 0, r + (d.size or 48) * 0.6), d.size or 48, d.size or 48, color_white)
	end
end

hook.Add("PostDrawTranslucentRenderables", "sigf_world", function(depth, sky)
	if depth or sky then return end
	local now = CurTime()
	for id, s in pairs(sprites) do
		if s.die > 0 and now > s.die then
			sprites[id] = nil
		else
			local pos = s.pos
			if s.ent then
				local e = Entity(s.ent)
				pos = IsValid(e) and (e:GetPos() + (s.off or Vector(0, 0, e:OBBMaxs().z + s.size * 0.6))) or nil
			end
			if pos then
				render.SetMaterial(mat(s.mat))
				render.DrawSprite(pos, s.size, s.size, col(s.color, color_white))
			end
		end
	end
	for id, p in pairs(portals) do
		if p.die > 0 and now > p.die then
			portals[id] = nil
		else
			drawPortalEnd(p.a, p.ca, p.r or 60, now, p)
			drawPortalEnd(p.b, p.cb, p.r or 60, now, p)
		end
	end
end)

-- Client-side mod loading (sh.lua then cl.lua), then "hello" to the server: its timers start.
local function run(path)
	if not file.Exists(path, "LUA") then return end
	local ok, e = xpcall(function() include(path) end, debug.traceback)
	if not ok then print("SIGF_ERROR client " .. path .. ": " .. tostring(e)) end
end

function Sigf.LoadModClient()
	run("sigf_mod/sh.lua")
	run("sigf_mod/cl.lua")
end

hook.Add("InitPostEntity", "sigf_hello", function()
	net.Start("sigf_hello")
	net.SendToServer()
	print("SIGF_CLIENT_READY")
end)
