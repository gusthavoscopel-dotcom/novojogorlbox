--!nocheck
-- Gera o mapa de verdade fora do Studio e confere a geometria.
-- Pré-requisito: rojo build default.project.json -o build/MeuVizinhoEUmNPC.rbxlx
-- Rodar:  lune run tests/map.luau [saida.json]
--
-- O MapService roda sem alterações em cima do place gerado pelo Rojo, com as classes do
-- @lune/roblox, que recusam propriedades inexistentes e valores do tipo errado.
-- Depois verificamos:
--   * nenhum ponto onde NPCs param fica dentro de um obstáculo;
--   * esconderijos, balcão de encomendas e caixas de correio não estão enterrados em outras peças;
--   * toda casa fica dentro de um gramado (não invade rua nem calçada).

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local game = roblox.deserializePlace(fs.readFile("build/MeuVizinhoEUmNPC.rbxlx"))
local workspace = game:GetService("Workspace")

-- O CFrame.lookAt do Lune 0.10 inverte a direção quando o alvo está no eixo Z (no Roblox,
-- lookAt para -Z é a identidade). Usamos a definição do Roblox montada com fromMatrix.
local CFrameFixed = setmetatable({
	lookAt = function(at, target, up)
		local look = (target - at).Unit
		local right = look:Cross(up or roblox.Vector3.yAxis).Unit
		return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
	end,
}, { __index = roblox.CFrame })
assert(CFrameFixed.lookAt(roblox.Vector3.zero, roblox.Vector3.new(0, 0, -1)).LookVector.Z < -0.99)

local cache = {}
local function requireModule(module)
	if cache[module] == nil then
		local chunk = luau.load(module.Source, {
			debugName = module:GetFullName(),
			environment = {
				script = module,
				require = requireModule,
				game = game,
				workspace = workspace,
				Instance = roblox.Instance,
				Enum = roblox.Enum,
				Vector2 = roblox.Vector2,
				Vector3 = roblox.Vector3,
				CFrame = CFrameFixed,
				Color3 = roblox.Color3,
				UDim = roblox.UDim,
				UDim2 = roblox.UDim2,
				warn = function(...)
					error("warn chamado durante a construção: " .. table.concat({ ... }, " "))
				end,
			},
		})
		cache[module] = chunk()
	end
	return cache[module]
end

local MapService = requireModule(game.ServerScriptService.Services.MapService)
local MapConfig = requireModule(game.ReplicatedStorage.Shared.Config.MapConfig)
MapService.Start()

local map = workspace:FindFirstChild("ActiveMap")
local lobby = workspace:FindFirstChild("Lobby")
assert(map and lobby, "ActiveMap/Lobby não foram criados")

local parts = {}
for _, root in { map, lobby } do
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
end

local TOP = MapConfig.BlockTop
local function isObstacle(p)
	if not p.CanCollide then
		return false
	end
	local top = p.CFrame.Position.Y + p.Size.Y / 2 -- suficiente: peças de piso não são giradas no eixo X/Z
	return top > TOP + 0.35
end

local function inside(p, point, margin)
	local localPoint = p.CFrame:PointToObjectSpace(point)
	local half = p.Size / 2 + roblox.Vector3.new(margin, margin, margin)
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

local problems = {}
local function problem(text)
	table.insert(problems, text)
end

-- 1) pontos de parada dos moradores (corpo aproximado por pontos nos pés, cintura e cabeça)
local state = 12345
local fakeRng = {}
function fakeRng:NextNumber()
	state = (state * 16807) % 2147483647
	return (state - 1) / 2147483646
end

local bodyOffsets = {}
for _, y in { 1, 2.5, 4.5 } do
	for _, xz in { { 0, 0 }, { 1.2, 0 }, { -1.2, 0 }, { 0, 1.2 }, { 0, -1.2 } } do
		table.insert(bodyOffsets, roblox.Vector3.new(xz[1], y, xz[2]))
	end
end

-- só obstáculos perto da zona (as chamadas de CFrame no Lune são lentas)
local obstacles = {}
for _, p in parts do
	if isObstacle(p) then
		table.insert(obstacles, { Part = p, Position = p.CFrame.Position, Reach = p.Size.Magnitude / 2 })
	end
end

for _, poi in MapConfig.Pois do
	local nearby = {}
	for _, o in obstacles do
		local dx, dz = o.Position.X - poi.Position.X, o.Position.Z - poi.Position.Z
		if math.sqrt(dx * dx + dz * dz) <= poi.ZoneRadius + o.Reach + 2 then
			table.insert(nearby, o.Part)
		end
	end
	local hits = {}
	for _ = 1, 300 do
		local stand = MapService.GetStandPoint(poi.Id, fakeRng)
		local feet = roblox.Vector3.new(stand.X, TOP, stand.Z)
		assert(MapService.GetPoiAt(stand) == poi.Id, poi.Id .. ": ponto de parada fora da própria zona")
		for _, p in nearby do
			for _, offset in bodyOffsets do
				if inside(p, feet + offset, 0) then
					hits[p:GetFullName()] = true
				end
			end
		end
	end
	for name in hits do
		problem(poi.Id .. ": morador pode parar dentro de " .. name)
	end
end

-- 2) objetos interativos não podem estar dentro de outras peças
local function checkClear(target, label)
	for _, p in parts do
		if p ~= target and isObstacle(p) and p.Parent ~= target.Parent and inside(p, target.CFrame.Position, -0.2) then
			problem(label .. " sobreposto a " .. p:GetFullName())
		end
	end
end
for _, d in map:GetDescendants() do
	if d:IsA("ProximityPrompt") then
		checkClear(d.Parent, "prompt " .. d:GetAttribute("Action") .. " em " .. d.Parent:GetFullName())
	end
end

-- 3) casas dentro de algum gramado (e não na rua ou calçada)
local lawns = {}
for _, p in map:GetDescendants() do
	if p:IsA("BasePart") and p.Name == "Gramado" then
		table.insert(lawns, p)
	end
end
for _, poi in MapConfig.Pois do
	if poi.Kind == "House" then
		local body = map:FindFirstChild(poi.Id):FindFirstChild("Corpo")
		local ok = false
		for _, lawn in lawns do
			local corners = 0
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = body.CFrame:PointToWorldSpace(roblox.Vector3.new(sx * body.Size.X / 2, 0, sz * body.Size.Z / 2))
					if math.abs(corner.X - lawn.CFrame.Position.X) <= lawn.Size.X / 2 and math.abs(corner.Z - lawn.CFrame.Position.Z) <= lawn.Size.Z / 2 then
						corners += 1
					end
				end
			end
			ok = ok or corners == 4
		end
		if not ok then
			problem(poi.Id .. ": casa fora do gramado (invade calçada ou rua)")
		end
	end
end

-- 4) zonas de POIs não se sobrepõem (cada posição pertence a um lugar só)
for i, a in MapConfig.Pois do
	for j = i + 1, #MapConfig.Pois do
		local b = MapConfig.Pois[j]
		local dx, dz = a.Position.X - b.Position.X, a.Position.Z - b.Position.Z
		if math.sqrt(dx * dx + dz * dz) < a.ZoneRadius + b.ZoneRadius then
			problem("zonas sobrepostas: " .. a.Id .. " e " .. b.Id)
		end
	end
end

print(string.format("Mapa gerado: %d peças (%d no lobby)", #parts, #lobby:GetDescendants()))

-- Exporta as peças para gerar a imagem de cima (tests/render_map.py)
local out = process.args[1]
if out then
	local export = {}
	for _, p in parts do
		local cf = p.CFrame
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		table.insert(export, {
			name = p.Name,
			shape = if p:IsA("Part") then p.Shape.Name else p.ClassName,
			size = { p.Size.X, p.Size.Y, p.Size.Z },
			pos = { cf.Position.X, cf.Position.Y, cf.Position.Z },
			rot = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
			color = { p.Color.R, p.Color.G, p.Color.B },
			transparency = p.Transparency,
		})
	end
	local pois = {}
	for _, poi in MapConfig.Pois do
		table.insert(pois, { id = poi.Id, x = poi.Position.X, z = poi.Position.Z, zone = poi.ZoneRadius })
	end
	fs.writeFile(out, serde.encode("json", { parts = export, pois = pois }))
	print("Peças exportadas para " .. out)
end

if #problems > 0 then
	for _, text in problems do
		print("PROBLEMA: " .. text)
	end
	process.exit(1)
end
print("Geometria OK")
