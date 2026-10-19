--!nocheck
-- Testes da lógica pura e da consistência das configurações, fora do Roblox Studio.
-- Rodar na raiz do repositório:  lune run tests/run.luau
--
-- Um "require" mínimo imita a árvore do Roblox a partir das pastas do Rojo, então os módulos
-- rodam sem alteração. Só funciona para módulos que não usam serviços do Roblox em tempo de execução.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local SERVICES = {
	ReplicatedStorage = "src/ReplicatedStorage",
	ServerScriptService = "src/ServerScriptService",
}

local loaded = {}
local shimRequire

-- fs.* pode pausar a thread, o que não é permitido dentro de __index; indexamos os arquivos antes
local files, dirs = {}, {}
local function scan(dir: string)
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		else
			files[path] = true
		end
	end
end
scan("src")

local function node(path: string, isModule: boolean)
	return setmetatable({ __path = path, __module = isModule }, {
		__index = function(self, key)
			local base = if self.__module then string.match(self.__path, "^(.*)/[^/]+$") else self.__path
			if key == "Parent" then
				local dir = if self.__module then base else string.match(self.__path, "^(.*)/[^/]+$")
				return node(dir, false)
			end
			if key == "WaitForChild" or key == "FindFirstChild" then
				return function(this, name)
					return this[name]
				end
			end
			if self.__module then
				error("filhos de ModuleScript não suportados no teste: " .. key)
			end
			if files[base .. "/" .. key .. ".luau"] then
				return node(base .. "/" .. key .. ".luau", true)
			elseif dirs[base .. "/" .. key] then
				return node(base .. "/" .. key, false)
			end
			error("instância não encontrada: " .. base .. "/" .. key)
		end,
	})
end

local fakeGame = {
	GetService = function(_, name)
		return node(assert(SERVICES[name], "serviço não simulado: " .. name), false)
	end,
}

function shimRequire(target)
	local path = target.__path
	if loaded[path] == nil then
		local chunk = luau.load(fs.readFile(path), {
			debugName = path,
			environment = {
				script = target,
				require = shimRequire,
				game = fakeGame,
				Vector3 = roblox.Vector3,
				Color3 = roblox.Color3,
			},
		})
		loaded[path] = chunk()
	end
	return loaded[path]
end

local function load(path: string)
	return shimRequire(node(path, true))
end

-- Gerador determinístico (Park–Miller) com a mesma interface do Random do Roblox
local function makeRng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local rng = {}
	function rng:NextNumber()
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
	function rng:NextInteger(min, max)
		return min + math.floor(self:NextNumber() * (max - min + 1) - 1e-9)
	end
	return rng
end

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FALHOU: " .. name .. "\n    " .. tostring(err))
	end
end

local function eq(actual, expected, message: string?)
	if actual ~= expected then
		error(string.format("%s: esperado %s, obtido %s", message or "valor", tostring(expected), tostring(actual)), 2)
	end
end

local GameConfig = load("src/ReplicatedStorage/Shared/Config/GameConfig.luau")
local CharacterConfig = load("src/ReplicatedStorage/Shared/Config/CharacterConfig.luau")
local RoutineConfig = load("src/ReplicatedStorage/Shared/Config/RoutineConfig.luau")
local MissionConfig = load("src/ReplicatedStorage/Shared/Config/MissionConfig.luau")
local MapConfig = load("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local MatchSetup = load("src/ServerScriptService/Logic/MatchSetup.luau")
local RoutinePlanner = load("src/ServerScriptService/Logic/RoutinePlanner.luau")
local MissionLogic = load("src/ServerScriptService/Logic/MissionLogic.luau")

local poiById, publicIds, houseIds = {}, {}, {}
for _, poi in MapConfig.Pois do
	poiById[poi.Id] = poi
	table.insert(if poi.Kind == "House" then houseIds else publicIds, poi.Id)
end

---------------------------------------------------------------------------
-- Consistência das configurações
---------------------------------------------------------------------------

test("ids únicos de personagens, POIs e esconderijos", function()
	for _, group in { { CharacterConfig.List, "CharacterId" }, { MapConfig.Pois, "Id" }, { MapConfig.Spots, "Id" } } do
		local seen = {}
		for _, item in group[1] do
			local id = item[group[2]]
			assert(not seen[id], "id repetido: " .. id)
			seen[id] = true
		end
	end
end)

test("personagens apontam para casas, trabalhos, rotinas e missões que existem", function()
	local templateIds = {}
	for _, template in MissionConfig.Templates do
		templateIds[template.Id] = true
	end
	for _, c in CharacterConfig.List do
		local home = poiById[c.HomeId]
		assert(home and home.Kind == "House", c.CharacterId .. ": HomeId inválido")
		assert(c.WorkPoi == nil or (poiById[c.WorkPoi] and poiById[c.WorkPoi].Kind == "Public"), c.CharacterId .. ": WorkPoi inválido")
		assert(RoutineConfig.Types[c.RoutineType], c.CharacterId .. ": RoutineType inválido")
		assert(c.ModelName ~= "", c.CharacterId .. ": ModelName vazio")
		if c.MissionPool then
			assert(#c.MissionPool >= GameConfig.MissionsPerPlayer, c.CharacterId .. ": MissionPool menor que MissionsPerPlayer")
			for _, id in c.MissionPool do
				assert(templateIds[id], c.CharacterId .. ": missão inexistente " .. id)
			end
		end
	end
end)

test("passos das rotinas são destinos válidos", function()
	local function valid(step)
		return step == "Home" or step == "Work" or step == "Neighbor" or (poiById[step] and poiById[step].Kind == "Public")
	end
	for name, routine in RoutineConfig.Types do
		assert(#routine.Sequence > 0, name .. ": sequência vazia")
		for _, step in routine.Sequence do
			assert(valid(step), name .. ": passo inválido " .. step)
		end
		for step in routine.Alternatives do
			assert(valid(step), name .. ": alternativa inválida " .. step)
		end
	end
end)

test("modelos de missão têm tipo suportado e campos obrigatórios", function()
	for _, t in MissionConfig.Templates do
		assert(MissionLogic.SupportedTypes[t.Type], t.Id .. ": tipo sem implementação " .. t.Type)
		assert(t.Reward > 0 and t.Weight > 0, t.Id .. ": recompensa/peso inválidos")
		assert(#t.AllowedRoles > 0, t.Id .. ": sem papel permitido")
	end
	assert(#MissionConfig.Templates >= GameConfig.MissionsPerPlayer, "poucos modelos de missão")
end)

test("limites do GameConfig são coerentes", function()
	assert(GameConfig.MinNPCs <= GameConfig.MaxActiveNPCs, "MinNPCs > MaxActiveNPCs")
	assert(GameConfig.MinPlayers >= 1, "MinPlayers < 1")
	assert(MatchSetup.MaxPlayers(#CharacterConfig.List, GameConfig.MaxParticipants, GameConfig.MinNPCs) >= GameConfig.MinPlayers)
	assert(GameConfig.RoundDuration > GameConfig.NPCReturnHomeTime)
end)

test("esconderijos e áreas de parada ficam dentro do mapa", function()
	local half = MapConfig.MapHalfSize - 6
	for _, spot in MapConfig.Spots do
		assert(math.abs(spot.Position.X) < half and math.abs(spot.Position.Z) < half, spot.Id .. " fora do mapa")
	end
	for _, poi in MapConfig.Pois do
		assert(poi.Stand.Radius < poi.ZoneRadius, poi.Id .. ": área de parada maior que a zona")
	end
end)

---------------------------------------------------------------------------
-- MatchSetup
---------------------------------------------------------------------------

local limits = { TargetResidents = GameConfig.TargetResidents, MinNPCs = GameConfig.MinNPCs, MaxActiveNPCs = GameConfig.MaxActiveNPCs }

test("PickResidents sempre inclui os principais e respeita os limites", function()
	for players = 0, MatchSetup.MaxPlayers(#CharacterConfig.List, GameConfig.MaxParticipants, GameConfig.MinNPCs) do
		local picked = MatchSetup.PickResidents(CharacterConfig.List, players, limits, makeRng(players + 7))
		local npcs = #picked - players
		assert(npcs >= GameConfig.MinNPCs and npcs <= GameConfig.MaxActiveNPCs, "NPCs fora do limite com " .. players .. " jogadores")
		local seen = {}
		for _, id in picked do
			assert(not seen[id], "morador repetido")
			seen[id] = true
		end
		for _, c in CharacterConfig.List do
			if c.IsMain then
				assert(seen[c.CharacterId], "principal ausente: " .. c.CharacterId)
			end
		end
	end
end)

test("AssignPlayers dá um morador diferente a cada jogador e o resto vira NPC", function()
	local residents = MatchSetup.PickResidents(CharacterConfig.List, 3, limits, makeRng(1))
	local byPlayer, npcs = MatchSetup.AssignPlayers(residents, { "A", "B", "C" }, makeRng(2))
	local used = {}
	for _, p in { "A", "B", "C" } do
		assert(byPlayer[p] and not used[byPlayer[p]], "jogador sem morador ou repetido")
		used[byPlayer[p]] = true
	end
	eq(#npcs, #residents - 3, "quantidade de NPCs")
	for _, id in npcs do
		assert(not used[id], "NPC também é jogador")
	end
end)

test("mesma seed gera a mesma partida", function()
	local a = MatchSetup.PickResidents(CharacterConfig.List, 2, limits, makeRng(99))
	local b = MatchSetup.PickResidents(CharacterConfig.List, 2, limits, makeRng(99))
	eq(table.concat(a, ","), table.concat(b, ","), "sorteio")
end)

---------------------------------------------------------------------------
-- RoutinePlanner
---------------------------------------------------------------------------

test("planner nunca repete o lugar atual e só escolhe destinos válidos", function()
	for _, c in CharacterConfig.List do
		local neighbors = {}
		for _, id in houseIds do
			if id ~= c.HomeId then
				table.insert(neighbors, id)
			end
		end
		local planner = RoutinePlanner.new(
			RoutineConfig.Types[c.RoutineType],
			{ Home = c.HomeId, Work = c.WorkPoi, Neighbors = neighbors },
			c.Personality,
			GameConfig.NPCReturnHomeTime,
			makeRng(#c.CharacterId * 31)
		)
		local current = c.HomeId
		local visited = {}
		for _ = 1, 300 do
			local activity = planner.Next({ TimeLeft = 300, CurrentPoi = current })
			assert(activity.PoiId ~= current, c.CharacterId .. ": repetiu " .. current)
			assert(poiById[activity.PoiId], c.CharacterId .. ": destino inexistente " .. activity.PoiId)
			assert(activity.Duration > 0 and activity.Delay >= 0 and activity.Delay <= 5, "duração/atraso inválidos")
			visited[activity.PoiId] = true
			current = activity.PoiId
		end
		local count = 0
		for _ in visited do
			count += 1
		end
		assert(count >= 3, c.CharacterId .. ": rotina pouco variada")
	end
end)

test("planner volta para casa no fim da rodada", function()
	local c = CharacterConfig.ById.Yuri22
	local planner = RoutinePlanner.new(RoutineConfig.Types[c.RoutineType], { Home = c.HomeId, Neighbors = {} }, c.Personality, 45, makeRng(3))
	local activity = planner.Next({ TimeLeft = 30, CurrentPoi = "Praca" })
	eq(activity.PoiId, c.HomeId, "destino")
	assert(activity.IsHome and activity.Duration >= 30, "deveria ficar em casa até o fim")
end)

---------------------------------------------------------------------------
-- MissionLogic
---------------------------------------------------------------------------

local function context(overrides)
	local residents = {}
	for _, c in CharacterConfig.List do
		table.insert(residents, { Id = c.CharacterId, Name = c.DisplayName })
	end
	local publicPois, houses = {}, {}
	for _, poi in MapConfig.Pois do
		table.insert(if poi.Kind == "House" then houses else publicPois, { Id = poi.Id, Name = poi.DisplayName })
	end
	local spots = {}
	for _, s in MapConfig.Spots do
		table.insert(spots, { Id = s.Id, Area = s.Area })
	end
	local ctx = {
		Role = "Morador",
		Count = 3,
		SelfResident = "Dona",
		Home = "CasaDona",
		Residents = residents,
		PublicPois = publicPois,
		Houses = houses,
		Spots = spots,
		Now = 1000,
	}
	for k, v in overrides or {} do
		ctx[k] = v
	end
	return ctx
end

local function templateOnly(id: string)
	for _, t in MissionConfig.Templates do
		if t.Id == id then
			return { t }
		end
	end
	error("modelo inexistente " .. id)
end

local function single(id: string, seed: number?)
	return MissionLogic.Generate(templateOnly(id), context({ Count = 1 }), makeRng(seed or 5))[1]
end

test("Generate cria missões de modelos diferentes sem envolver o próprio jogador", function()
	for seed = 1, 50 do
		local missions = MissionLogic.Generate(MissionConfig.Templates, context(), makeRng(seed))
		eq(#missions, 3, "quantidade")
		local seen = {}
		for _, m in missions do
			assert(not seen[m.TemplateId], "modelo repetido")
			seen[m.TemplateId] = true
			assert(not table.find(m.Targets, "Dona"), "alvo é o próprio jogador")
			assert(not table.find(m.Targets, "CasaDona"), "alvo é a própria casa")
			assert(not string.find(m.Description, "{", 1, true), "texto sem preencher: " .. m.Description)
		end
	end
end)

test("Generate respeita MissionPool e papel", function()
	local missions = MissionLogic.Generate(MissionConfig.Templates, context({ Pool = { "Papo", "Ronda", "Achados" } }), makeRng(4))
	for _, m in missions do
		assert(table.find({ "Papo", "Ronda", "Achados" }, m.TemplateId), "fora do pool")
	end
	eq(#MissionLogic.Generate(MissionConfig.Templates, context({ Role = "Ninguem" }), makeRng(4)), 0, "papel sem missões")
end)

test("Visit conta cada lugar uma vez e congela ao concluir", function()
	local m = single("Passeio")
	assert(not MissionLogic.Apply(m, "EnterPoi", "LugarQueNaoExiste"), "aceitou alvo inválido")
	assert(MissionLogic.Apply(m, "EnterPoi", m.Targets[1]))
	assert(not MissionLogic.Apply(m, "EnterPoi", m.Targets[1]), "contou duas vezes")
	assert(not MissionLogic.Apply(m, "Talk", m.Targets[2]), "evento errado contou")
	MissionLogic.Apply(m, "EnterPoi", m.Targets[2])
	MissionLogic.Apply(m, "EnterPoi", m.Targets[3])
	eq(m.Status, "Completed", "status")
	assert(not MissionLogic.Apply(m, "EnterPoi", m.Targets[3]), "mudou depois de concluída")
	eq(MissionLogic.View(m).ProgressText, "3/3", "texto")
end)

test("Talk só conta os moradores sorteados", function()
	local m = single("Papo")
	assert(not MissionLogic.Apply(m, "Talk", "Dona"), "contou conversa consigo mesmo")
	MissionLogic.Apply(m, "Talk", m.Targets[1])
	MissionLogic.Apply(m, "Talk", m.Targets[2])
	eq(m.Status, "Completed", "status")
end)

test("Deliver exige retirar antes e entregar na casa certa", function()
	local m = single("Entrega")
	assert(not MissionLogic.Apply(m, "Deliver", m.Targets[1]), "entregou sem retirar")
	assert(MissionLogic.Apply(m, "Pickup"))
	assert(not MissionLogic.Apply(m, "Pickup"), "retirou duas vezes")
	assert(not MissionLogic.Apply(m, "Deliver", "CasaQueNaoEh"), "entregou na casa errada")
	assert(MissionLogic.Apply(m, "Deliver", m.Targets[1]))
	eq(m.Status, "Completed", "status")
	eq(MissionLogic.View(m).ProgressText, "Entregue!", "texto")
end)

test("Find só conclui no esconderijo secreto", function()
	local m = single("Achados")
	for _, spot in MapConfig.Spots do
		if spot.Id ~= m.Targets[1] then
			assert(not MissionLogic.Apply(m, "Search", spot.Id), "achou no lugar errado")
		end
	end
	assert(MissionLogic.Apply(m, "Search", m.Targets[1]))
	eq(m.Status, "Completed", "status")
end)

test("Follow só soma tempo dentro do raio", function()
	local m = single("Sombra")
	assert(not MissionLogic.TickFollow(m, 10, m.Radius + 1), "contou fora do raio")
	assert(not MissionLogic.TickFollow(m, 10, nil), "contou alvo ausente")
	eq(m.Progress, 0, "progresso fora do raio")
	for _ = 1, 100 do
		MissionLogic.TickFollow(m, 0.5, m.Radius - 1)
	end
	eq(m.Status, "Completed", "status")
	eq(m.Progress, m.Goal, "progresso limitado à meta")
end)

test("missão expira pelo TimeLimit e não avança mais", function()
	local m = single("Entrega")
	assert(m.ExpiresAt == 1000 + 240, "ExpiresAt")
	assert(not MissionLogic.Expire(m, 1100), "expirou cedo")
	assert(MissionLogic.Expire(m, 1240))
	eq(m.Status, "Failed", "status")
	assert(not MissionLogic.Apply(m, "Pickup"), "avançou depois de falhar")
end)

test("saída do alvo cancela, mas não se aquele alvo já foi cumprido", function()
	local m = single("Papo")
	MissionLogic.Apply(m, "Talk", m.Targets[1])
	assert(not MissionLogic.CancelIfTarget(m, m.Targets[1]), "cancelou por alvo já cumprido")
	assert(MissionLogic.CancelIfTarget(m, m.Targets[2]))
	eq(m.Status, "Cancelled", "status")
	local visit = single("Passeio")
	assert(not MissionLogic.CancelIfTarget(visit, "Yuri22"), "cancelou missão sem morador-alvo")
end)

test("fim da rodada falha só as missões ativas", function()
	local done = single("Achados")
	MissionLogic.Apply(done, "Search", done.Targets[1])
	local open = single("Passeio")
	assert(not MissionLogic.Finish(done))
	assert(MissionLogic.Finish(open))
	eq(done.Status, "Completed", "concluída")
	eq(open.Status, "Failed", "aberta")
end)

print(string.format("%d testes passaram, %d falharam", passed, failed))
if failed > 0 then
	process.exit(1)
end
