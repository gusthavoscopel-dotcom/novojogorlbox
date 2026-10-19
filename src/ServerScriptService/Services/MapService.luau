--!strict
-- Gera o lobby e o bairro a partir do MapConfig (uma vez, ao iniciar o servidor) e responde
-- perguntas espaciais: em qual ponto de interesse uma posição está e onde um morador pode parar.
-- Toda a geometria é feita de Parts simples; os modelos ficam em Workspace.ActiveMap e Workspace.Lobby.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)

type Poi = MapConfig.Poi
type Spot = MapConfig.Spot

local MapService = {}

local COLORS = MapConfig.Colors
local TOP = MapConfig.BlockTop
local HOUSE = Vector3.new(16, 10, 14) -- largura, altura, profundidade
local PORCH_DEPTH = 5
local ROOF_HEIGHT = 5

local poiById: { [string]: Poi } = {}
for _, poi in MapConfig.Pois do
	poiById[poi.Id] = poi
end

---------------------------------------------------------------------------
-- Primitivas
---------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Cilindro em pé (no Roblox o eixo do cilindro é o X da peça)
local function cylinder(parent: Instance, name: string, height: number, diameter: number, center: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, diameter: number, center: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.one * diameter, CFrame.new(center), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Placa flutuante legível de longe (tamanho em studs)
local function sign(adornee: BasePart, text: string, offset: Vector3, width: number, height: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Placa"
	gui.Size = UDim2.fromScale(width, height or 2.6)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 170
	gui.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(45, 42, 62)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.Text = text
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label

	gui.Parent = adornee
end

-- Prompt de interação; Action/atributos são lidos e validados pelo InteractionService
local function prompt(parent: BasePart, action: string, actionText: string, objectText: string, attributes: { [string]: string }, hold: number)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = actionText
	pp.ObjectText = objectText
	pp.HoldDuration = hold
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	pp:SetAttribute("Action", action)
	for key, value in attributes do
		pp:SetAttribute(key, value)
	end
	pp.Parent = parent
end

---------------------------------------------------------------------------
-- Decoração reutilizável
---------------------------------------------------------------------------

-- cf aponta para onde o banco "olha"; o encosto fica atrás (+Z local)
local function bench(parent: Instance, cf: CFrame)
	part(parent, "Assento", Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.6, 0), COLORS.Wood, Enum.Material.WoodPlanks)
	part(parent, "Encosto", Vector3.new(6, 2, 0.4), cf * CFrame.new(0, 2.8, 0.9), COLORS.Wood, Enum.Material.WoodPlanks)
	for _, x in { -2.5, 2.5 } do
		part(parent, "Pe", Vector3.new(0.4, 1.4, 1.6), cf * CFrame.new(x, 0.7, 0), COLORS.Metal, Enum.Material.Metal)
	end
end

local function tree(parent: Instance, base: Vector3)
	cylinder(parent, "Tronco", 6, 1.6, base + Vector3.new(0, 3, 0), COLORS.Trunk, Enum.Material.Wood)
	-- copa sem colisão: dá para passar por baixo e não atrapalha o pathfinding
	ball(parent, "Copa", 9, base + Vector3.new(0, 8, 0), COLORS.Leaves, Enum.Material.Grass).CanCollide = false
end

---------------------------------------------------------------------------
-- Estrutura do bairro
---------------------------------------------------------------------------

local function buildGround(map: Instance)
	local size = MapConfig.MapHalfSize * 2
	part(map, "Asfalto", Vector3.new(size, 2, size), CFrame.new(0, MapConfig.GroundTop - 1, 0), COLORS.Asphalt, Enum.Material.Asphalt)

	-- faixa amarela no meio de cada rua (internas e anel externo)
	local pitch = MapConfig.BlockPitch
	local lineY = MapConfig.GroundTop + 0.025
	for _, offset in { -pitch / 2, pitch / 2, -pitch * 1.5, pitch * 1.5 } do
		part(map, "Faixa", Vector3.new(size - 8, 0.05, 0.6), CFrame.new(0, lineY, offset), COLORS.StreetLine)
		part(map, "Faixa", Vector3.new(0.6, 0.05, size - 8), CFrame.new(offset, lineY, 0), COLORS.StreetLine)
	end

	-- cerca viva que limita o bairro
	local edge = MapConfig.MapHalfSize - 2
	for _, side in { -1, 1 } do
		part(map, "CercaViva", Vector3.new(size, 8, 4), CFrame.new(0, MapConfig.GroundTop + 4, edge * side), COLORS.Hedge, Enum.Material.LeafyGrass)
		part(map, "CercaViva", Vector3.new(4, 8, size), CFrame.new(edge * side, MapConfig.GroundTop + 4, 0), COLORS.Hedge, Enum.Material.LeafyGrass)
	end
end

-- Quarteirão: calçada em volta e miolo (gramado ou piso da praça), tudo na mesma altura
local function buildBlock(map: Instance, cx: number, cz: number, kind: string)
	local size = MapConfig.BlockSize
	local walk = MapConfig.SidewalkWidth
	local inner = size - walk * 2
	local thickness = TOP - MapConfig.GroundTop
	local y = MapConfig.GroundTop + thickness / 2
	local edge = size / 2 - walk / 2
	local block = model(map, "Quarteirao_" .. kind)

	part(block, "Calcada", Vector3.new(size, thickness, walk), CFrame.new(cx, y, cz - edge), COLORS.Sidewalk, Enum.Material.Concrete)
	part(block, "Calcada", Vector3.new(size, thickness, walk), CFrame.new(cx, y, cz + edge), COLORS.Sidewalk, Enum.Material.Concrete)
	part(block, "Calcada", Vector3.new(walk, thickness, inner), CFrame.new(cx - edge, y, cz), COLORS.Sidewalk, Enum.Material.Concrete)
	part(block, "Calcada", Vector3.new(walk, thickness, inner), CFrame.new(cx + edge, y, cz), COLORS.Sidewalk, Enum.Material.Concrete)

	if kind == "Plaza" then
		part(block, "Piso", Vector3.new(inner, thickness, inner), CFrame.new(cx, y, cz), COLORS.Plaza, Enum.Material.Cobblestone)
	else
		part(block, "Gramado", Vector3.new(inner, thickness, inner), CFrame.new(cx, y, cz), COLORS.Lot, Enum.Material.Grass)
	end
end

local function buildHouse(map: Instance, poi: Poi)
	local facing = poi.Facing or Vector3.zAxis
	local center = poi.Position - facing * (HOUSE.Z / 2 + PORCH_DEPTH)
	local base = CFrame.lookAt(center, center + facing) -- LookVector (-Z local) = fachada
	local wallColor = poi.Color or Color3.new(1, 1, 1)
	local house = model(map, poi.Id)

	local body = part(house, "Corpo", HOUSE, base * CFrame.new(0, HOUSE.Y / 2, 0), wallColor, Enum.Material.Plaster)

	-- telhado de duas águas: a rampa da WedgePart sobe em direção ao +Z local dela
	local roofSize = Vector3.new(HOUSE.X + 2, ROOF_HEIGHT, HOUSE.Z / 2 + 1)
	for _, side in { -1, 1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Telhado"
		wedge.Anchored = true
		wedge.Size = roofSize
		wedge.Color = poi.RoofColor or Color3.fromRGB(120, 62, 52)
		wedge.Material = Enum.Material.RoofShingles
		local turn = if side == 1 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
		wedge.CFrame = base * CFrame.new(0, HOUSE.Y + ROOF_HEIGHT / 2, side * roofSize.Z / 2) * turn
		wedge.Parent = house
	end

	local front = -HOUSE.Z / 2
	part(house, "Porta", Vector3.new(4, 7, 0.4), base * CFrame.new(0, 3.5, front - 0.2), COLORS.Wood, Enum.Material.Wood)
	for _, x in { -5, 5 } do
		part(house, "Janela", Vector3.new(3, 3, 0.2), base * CFrame.new(x, 6, front - 0.1), Color3.fromRGB(179, 229, 252), Enum.Material.Glass)
	end

	-- caminho da porta até a calçada
	part(house, "Caminho", Vector3.new(4, 0.1, 9), base * CFrame.new(0, 0.05, front - 4.5), COLORS.Sidewalk, Enum.Material.Pavement)

	-- caixa de correio (destino da missão de entrega)
	local mailbox = base * CFrame.new(5.5, 0, front - PORCH_DEPTH + 1)
	part(house, "PosteCorreio", Vector3.new(0.4, 3.2, 0.4), mailbox * CFrame.new(0, 1.6, 0), COLORS.Metal, Enum.Material.Metal)
	local box = part(house, "CaixaDeCorreio", Vector3.new(1.6, 1.2, 2.2), mailbox * CFrame.new(0, 3.6, 0), Color3.fromRGB(229, 57, 53))
	prompt(box, "Deliver", "Entregar encomenda", "Caixa de correio", { HouseId = poi.Id }, 0.5)

	sign(body, poi.DisplayName, Vector3.new(0, HOUSE.Y / 2 + ROOF_HEIGHT + 2.5, 0), 13)
end

-- Mercado e Lanchonete: pavilhão aberto (dá para entrar por três lados)
local function buildPavilion(map: Instance, poi: Poi)
	local size = poi.Size or Vector3.new(30, 11, 20)
	local facing = poi.Facing or Vector3.zAxis
	local base = CFrame.lookAt(poi.Position, poi.Position + facing)
	local color = poi.Color or Color3.new(1, 1, 1)
	local building = model(map, poi.Id)

	part(building, "Piso", Vector3.new(size.X, 0.2, size.Z), base * CFrame.new(0, 0.1, 0), Color3.fromRGB(240, 230, 210), Enum.Material.WoodPlanks)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(building, "Coluna", Vector3.new(1, size.Y, 1), base * CFrame.new(x * (size.X / 2 - 0.5), size.Y / 2, z * (size.Z / 2 - 0.5)), Color3.new(1, 1, 1))
		end
	end
	part(building, "Fundo", Vector3.new(size.X, size.Y, 0.6), base * CFrame.new(0, size.Y / 2, size.Z / 2 - 0.3), color, Enum.Material.Plaster)
	local roof = part(building, "Telhado", Vector3.new(size.X + 2, 1, size.Z + 2), base * CFrame.new(0, size.Y + 0.5, 0), poi.RoofColor or color)
	part(building, "Toldo", Vector3.new(size.X + 2, 2.5, 0.4), base * CFrame.new(0, size.Y - 0.6, -size.Z / 2 - 1.2), color)
	part(building, "Balcao", Vector3.new(size.X - 8, 3.5, 2), base * CFrame.new(0, 1.75, size.Z / 2 - 3), COLORS.Wood, Enum.Material.WoodPlanks)

	-- produtos coloridos no balcão (só decoração)
	local palette = { Color3.fromRGB(239, 83, 80), Color3.fromRGB(255, 202, 40), Color3.fromRGB(102, 187, 106), Color3.fromRGB(66, 165, 245) }
	for i = 1, 6 do
		local x = -size.X / 2 + 6 + (i - 1) * (size.X - 12) / 5
		part(building, "Produto", Vector3.new(1.4, 1.6, 1.4), base * CFrame.new(x, 4.3, size.Z / 2 - 3), palette[(i - 1) % #palette + 1])
	end

	sign(roof, poi.DisplayName, Vector3.new(0, 4, 0), 18)
end

local function buildPackageCounter(map: Instance)
	local position = MapConfig.PackageCounter
	local booth = model(map, "BalcaoEncomendas")
	local counter = part(booth, "Balcao", Vector3.new(6, 3.5, 3), CFrame.new(position + Vector3.new(0, 1.75, 0)), COLORS.Wood, Enum.Material.WoodPlanks)
	part(booth, "Caixas", Vector3.new(2, 1.5, 2), CFrame.new(position + Vector3.new(-1.5, 4.25, 0)), Color3.fromRGB(210, 170, 110), Enum.Material.Cardboard)
	for _, x in { -2.8, 2.8 } do
		part(booth, "Poste", Vector3.new(0.4, 8, 0.4), CFrame.new(position + Vector3.new(x, 4, 1.3)), COLORS.Metal, Enum.Material.Metal)
	end
	local cover = part(booth, "Cobertura", Vector3.new(8, 0.5, 5), CFrame.new(position + Vector3.new(0, 8.25, 0)), Color3.fromRGB(255, 133, 64))
	prompt(counter, "Pickup", "Retirar encomenda", "Balcão de encomendas", {}, 0.5)
	sign(cover, "Encomendas", Vector3.new(0, 2.5, 0), 11)
end

local function buildPlaza(map: Instance, poi: Poi)
	local c = poi.Position
	local plaza = model(map, poi.Id)

	cylinder(plaza, "BaseChafariz", 1.6, 14, c + Vector3.new(0, 0.8, 0), Color3.fromRGB(189, 189, 189), Enum.Material.Concrete)
	cylinder(plaza, "Agua", 0.3, 12, c + Vector3.new(0, 1.5, 0), COLORS.Water, Enum.Material.Glass).Transparency = 0.3
	local column = cylinder(plaza, "Coluna", 4, 2, c + Vector3.new(0, 3, 0), Color3.fromRGB(224, 224, 224), Enum.Material.Marble)
	ball(plaza, "Topo", 3, c + Vector3.new(0, 5.5, 0), COLORS.Water, Enum.Material.Glass)

	for i = 0, 3 do
		local angle = i * math.pi / 2
		local seat = c + Vector3.new(math.cos(angle) * 32, 0, math.sin(angle) * 32)
		bench(plaza, CFrame.lookAt(seat, Vector3.new(c.X, seat.Y, c.Z)))
	end
	for _, x in { -36, 36 } do
		for _, z in { -36, 36 } do
			tree(plaza, c + Vector3.new(x, 0, z))
		end
	end

	sign(column, poi.DisplayName, Vector3.new(0, 8, 0), 18)
end

local function buildPark(map: Instance, poi: Poi)
	local c = poi.Position
	local park = model(map, poi.Id)

	local trees = { { -30, -30 }, { 0, -34 }, { 30, -30 }, { 34, 0 }, { 30, 30 }, { 0, 34 }, { -34, 0 } }
	for _, offset in trees do
		tree(park, c + Vector3.new(offset[1], 0, offset[2]))
	end
	local pond = cylinder(park, "Lago", 0.3, 14, c + Vector3.new(-28, 0.15, 28), COLORS.Water, Enum.Material.Glass)
	pond.Transparency = 0.2
	for _, offset in { Vector3.new(0, 0, -24), Vector3.new(24, 0, 0), Vector3.new(0, 0, 24) } do
		local seat = c + offset
		bench(park, CFrame.lookAt(seat, Vector3.new(c.X, seat.Y, c.Z)))
	end

	local post = part(park, "PostePlaca", Vector3.new(0.6, 6, 0.6), CFrame.new(c + Vector3.new(36, 3, -36)), COLORS.Wood, Enum.Material.Wood)
	sign(post, poi.DisplayName, Vector3.new(0, 5, 0), 12)
end

local function buildBusStop(map: Instance, poi: Poi)
	local facing = poi.Facing or Vector3.zAxis
	local center = poi.Position - facing * 5 -- abrigo atrás da área de espera
	local base = CFrame.lookAt(center, center + facing)
	local stop = model(map, poi.Id)

	local back = part(stop, "Fundo", Vector3.new(16, 7, 0.5), base * CFrame.new(0, 4.5, 2.75), Color3.fromRGB(207, 234, 250), Enum.Material.Glass)
	back.Transparency = 0.4
	for _, x in { -7.5, 7.5 } do
		part(stop, "Poste", Vector3.new(0.5, 8, 0.5), base * CFrame.new(x, 4, 2.75), COLORS.Metal, Enum.Material.Metal)
	end
	local cover = part(stop, "Cobertura", Vector3.new(18, 0.5, 7), base * CFrame.new(0, 8.25, 0), poi.Color or COLORS.Metal)
	bench(stop, base * CFrame.new(0, 0, 1.2))
	part(stop, "PostePlaca", Vector3.new(0.4, 9, 0.4), base * CFrame.new(-10, 4.5, -2), COLORS.Metal, Enum.Material.Metal)
	part(stop, "PlacaOnibus", Vector3.new(2.4, 2.4, 0.2), base * CFrame.new(-10, 8.4, -2), Color3.fromRGB(30, 136, 229))

	sign(cover, poi.DisplayName, Vector3.new(0, 3, 0), 16)
end

-- Esconderijos da missão "Achados e perdidos"
local function buildSpot(map: Instance, spot: Spot)
	local p = spot.Position
	local target: BasePart
	if spot.Kind == "Bush" then
		target = ball(map, spot.Id, 5, p + Vector3.new(0, 2, 0), Color3.fromRGB(56, 142, 60), Enum.Material.LeafyGrass)
	elseif spot.Kind == "Trash" then
		target = cylinder(map, spot.Id, 3, 2.4, p + Vector3.new(0, 1.5, 0), Color3.fromRGB(46, 125, 50), Enum.Material.Metal)
	else
		target = part(map, spot.Id, Vector3.new(3, 3, 3), CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0.3, 0), COLORS.Wood, Enum.Material.WoodPlanks)
		part(map, spot.Id .. "_Topo", Vector3.new(2.4, 2.4, 2.4), CFrame.new(p + Vector3.new(0.3, 4.2, 0.2)) * CFrame.Angles(0, -0.4, 0), COLORS.Wood, Enum.Material.WoodPlanks)
	end
	prompt(target, "Search", "Procurar", spot.DisplayName, { SpotId = spot.Id }, 1)
end

-- O SpawnLocation do lobby é o único do jogo: LoadCharacterAsync sempre nasce aqui
local function buildLobby()
	local cfg = MapConfig.Lobby
	local c = cfg.Center
	local size = cfg.Size
	local lobby = model(workspace, "Lobby")

	part(lobby, "Piso", Vector3.new(size, 2, size), CFrame.new(c - Vector3.new(0, 1, 0)), Color3.fromRGB(255, 236, 179), Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		local glassA = part(lobby, "Grade", Vector3.new(size, 12, 1), CFrame.new(c + Vector3.new(0, 6, side * (size / 2 - 0.5))), Color3.fromRGB(207, 234, 250), Enum.Material.Glass)
		local glassB = part(lobby, "Grade", Vector3.new(1, 12, size), CFrame.new(c + Vector3.new(side * (size / 2 - 0.5), 6, 0)), Color3.fromRGB(207, 234, 250), Enum.Material.Glass)
		glassA.Transparency = 0.6
		glassB.Transparency = 0.6
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(c + Vector3.new(0, 0.5, 8))
	spawn.Color = Color3.fromRGB(255, 133, 64)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Parent = lobby

	local post = part(lobby, "Letreiro", Vector3.new(1, 1, 1), CFrame.new(c + Vector3.new(0, 4, -size / 2 + 6)), Color3.new(1, 1, 1))
	post.Transparency = 1
	post.CanCollide = false
	sign(post, "<b>MEU VIZINHO É UM NPC</b>\nYuri22 &amp; Amigos", Vector3.new(0, 8, 0), 34, 8)
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function MapService.Start()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 165)

	buildLobby()

	local map = Instance.new("Folder")
	map.Name = "ActiveMap"
	buildGround(map)
	for _, block in MapConfig.Blocks do
		buildBlock(map, block.X * MapConfig.BlockPitch, block.Z * MapConfig.BlockPitch, block.Type)
	end

	local builders: { [string]: (Instance, Poi) -> () } = {
		House = buildHouse,
		Market = buildPavilion,
		Diner = buildPavilion,
		Plaza = buildPlaza,
		Park = buildPark,
		BusStop = buildBusStop,
	}
	for _, poi in MapConfig.Pois do
		local build = builders[poi.Building]
		if build then
			build(map, poi)
		else
			warn(`[MapService] tipo de prédio desconhecido: {poi.Building} ({poi.Id})`)
		end
	end
	buildPackageCounter(map)

	local hiding = Instance.new("Folder")
	hiding.Name = "Esconderijos"
	hiding.Parent = map
	for _, spot in MapConfig.Spots do
		buildSpot(hiding, spot)
	end

	map.Parent = workspace
end

-- Id do ponto de interesse onde a posição está (casas e lugares públicos), ou nil
function MapService.GetPoiAt(position: Vector3): string?
	if math.abs(position.Y - TOP) > 15 then
		return nil
	end
	for _, poi in MapConfig.Pois do
		local dx, dz = position.X - poi.Position.X, position.Z - poi.Position.Z
		if dx * dx + dz * dz <= poi.ZoneRadius * poi.ZoneRadius then
			return poi.Id
		end
	end
	return nil
end

-- Ponto aleatório (na altura do quadril) dentro da área de parada de um POI
function MapService.GetStandPoint(poiId: string, rng: Random): Vector3
	local poi = poiById[poiId]
	assert(poi, "POI desconhecido: " .. poiId)
	local stand = poi.Stand
	local center = poi.Position + (stand.Offset or Vector3.zero)
	local minRadius = stand.MinRadius or 0
	local angle = rng:NextNumber() * math.pi * 2
	local radius = minRadius + (stand.Radius - minRadius) * math.sqrt(rng:NextNumber())
	return Vector3.new(center.X + math.cos(angle) * radius, TOP + 3, center.Z + math.sin(angle) * radius)
end

return MapService
