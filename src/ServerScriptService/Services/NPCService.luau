--!strict
-- NPCs moradores: cria o modelo, anda pelo bairro com PathfindingService e executa a rotina
-- escolhida pelo RoutinePlanner. Máquina de estados da Fase 1:
--   Idle -> Walking/ReturningHome -> Working/Shopping/Idle (no destino), Talking (interrompido).
-- Cada NPC roda numa thread que passa a maior parte do tempo dormindo; NPCs longe de todos os
-- jogadores verificam o movimento com menos frequência.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AssetConfig = require(ReplicatedStorage.Shared.Config.AssetConfig)
local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local RoutineConfig = require(ReplicatedStorage.Shared.Config.RoutineConfig)
local RoutinePlanner = require(script.Parent.Parent.Logic.RoutinePlanner)
local CharacterService = require(script.Parent.CharacterService)
local MapService = require(script.Parent.MapService)

type Character = CharacterConfig.Character

type NPC = {
	Id: string,
	Config: Character,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Path: Path,
	Planner: RoutinePlanner.Planner,
	Rng: Random,
	State: string,
	CurrentPoi: string?,
	PausedUntil: number,
	Active: boolean,
	Connections: { RBXScriptConnection },
}

local NPCService = {}

local AGENT = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = false,
	AgentCanClimb = false,
	WaypointSpacing = 10,
	Costs = { Asphalt = 4, Grass = 2 }, -- prefere calçadas, como um morador de verdade
}
local MAX_PATH_ATTEMPTS = 3
local STAND_POINT_ATTEMPTS = 2
local RESPAWN_DELAY = 5
local DISCREET_DISTANCE = 80 -- teleporte de emergência só se nenhum jogador estiver perto

local npcs: { [string]: NPC } = {}
local roundActive = false
local getTimeLeft: () -> number = function()
	return math.huge
end

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- Modelos-base ficam em ServerStorage.NPCModels e são clonados a cada rodada.
-- Um Model com o mesmo ModelName colocado lá manualmente é usado no lugar do gerado.
local templates = folder(ServerStorage, "NPCModels")
local residentsFolder = folder(workspace, "Residents")

local neighborsOf: { [string]: { string } } = {}
for _, cfg in CharacterConfig.List do
	local list = {}
	for _, poi in MapConfig.Pois do
		if poi.Kind == "House" and poi.Id ~= cfg.HomeId then
			table.insert(list, poi.Id)
		end
	end
	neighborsOf[cfg.CharacterId] = list
end

local function getTemplate(cfg: Character): Model?
	local existing = templates:FindFirstChild(cfg.ModelName)
	if existing and existing:IsA("Model") then
		return existing
	end
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(CharacterService.GetDescription(cfg):Clone(), Enum.HumanoidRigType.R15)
	end)
	if not ok then
		warn(`[NPCService] não foi possível criar o modelo de {cfg.CharacterId}: {result}`)
		return nil
	end
	result.Name = cfg.ModelName
	result.Parent = templates
	return result
end

local function isNearAnyPlayer(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character.PrimaryPart
		if root and (root.Position - position).Magnitude <= distance then
			return true
		end
	end
	return false
end

local function pollInterval(npc: NPC): number
	return if isNearAnyPlayer(npc.Root.Position, GameConfig.NPCNearPlayerDistance) then 0.1 else 0.5
end

-- Para enquanto alguém conversa com o NPC
local function holdIfTalking(npc: NPC)
	if os.clock() >= npc.PausedUntil then
		return
	end
	local previous = npc.State
	npc.State = "Talking"
	while npc.Active and os.clock() < npc.PausedUntil do
		task.wait(0.2)
	end
	npc.State = previous
end

local function waitFor(npc: NPC, seconds: number)
	local deadline = os.clock() + seconds
	while npc.Active and os.clock() < deadline do
		holdIfTalking(npc)
		task.wait(math.clamp(deadline - os.clock(), 0.05, 1))
	end
end

local function moveTo(npc: NPC, target: Vector3): boolean
	local humanoid = npc.Humanoid
	local reached: boolean? = nil
	local connection = humanoid.MoveToFinished:Once(function(success)
		reached = success
	end)
	humanoid:MoveTo(target)
	local distance = (target - npc.Root.Position).Magnitude
	local deadline = os.clock() + distance / math.max(humanoid.WalkSpeed, 1) + 2
	while reached == nil and npc.Active and os.clock() < deadline do
		task.wait(pollInterval(npc))
	end
	connection:Disconnect()
	return reached == true
end

-- Segue um caminho calculado; recalcula se o caminho for bloqueado (até MAX_PATH_ATTEMPTS)
local function followPath(npc: NPC, target: Vector3): boolean
	local path = npc.Path
	for attempt = 1, MAX_PATH_ATTEMPTS do
		if not npc.Active then
			return false
		end
		local computed = pcall(path.ComputeAsync, path, npc.Root.Position, target)
		if computed and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			local current = 1
			local blocked = false
			local connection = path.Blocked:Connect(function(index)
				if index >= current then
					blocked = true
				end
			end)
			for i = 2, #waypoints do
				current = i
				holdIfTalking(npc)
				if blocked or not npc.Active or not moveTo(npc, waypoints[i].Position) then
					blocked = true
					break
				end
			end
			connection:Disconnect()
			if not blocked then
				return true
			end
		end
		task.wait(0.3 * attempt)
	end
	return false
end

local function walkToPoi(npc: NPC, poiId: string): boolean
	for _ = 1, STAND_POINT_ATTEMPTS do
		if followPath(npc, MapService.GetStandPoint(poiId, npc.Rng)) then
			return true
		end
		if not npc.Active then
			return false
		end
	end
	local target = MapService.GetStandPoint(poiId, npc.Rng)
	if moveTo(npc, target) then
		return true
	end
	-- último recurso para NPC preso: teleporte, mas só se ninguém estiver vendo
	if not isNearAnyPlayer(npc.Root.Position, DISCREET_DISTANCE) and not isNearAnyPlayer(target, DISCREET_DISTANCE) then
		npc.Model:PivotTo(CFrame.new(target))
		return true
	end
	return false
end

local function runBrain(npc: NPC)
	-- "acordando": cada morador sai de casa num momento diferente
	waitFor(npc, 1 + npc.Rng:NextNumber() * 5)
	while npc.Active do
		local activity = npc.Planner.Next({ TimeLeft = getTimeLeft(), CurrentPoi = npc.CurrentPoi })
		if activity.Delay > 0 then
			npc.State = "Idle"
			waitFor(npc, activity.Delay)
		end
		if not npc.Active then
			break
		end
		if activity.PoiId ~= npc.CurrentPoi then
			npc.State = if activity.IsHome then "ReturningHome" else "Walking"
			if walkToPoi(npc, activity.PoiId) then
				npc.CurrentPoi = activity.PoiId
			else
				npc.CurrentPoi = MapService.GetPoiAt(npc.Root.Position)
				npc.State = "Idle"
				waitFor(npc, 2)
				continue
			end
		end
		npc.State = activity.State
		waitFor(npc, activity.Duration)
	end
end

local function loadTrack(animator: Animator, animationId: string?): AnimationTrack?
	if not animationId or animationId == "" then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok then
		warn(`[NPCService] animação {animationId} não carregou: {track}`)
		return nil
	end
	track.Looped = true
	return track
end

-- Mesma mistura caminhada/corrida do script Animate padrão do R15, para o NPC andar igual a um jogador
local function setupAnimations(npc: NPC)
	local humanoid = npc.Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local overrides = npc.Config.AnimationConfig
	local defaults = AssetConfig.Animations
	local idle = loadTrack(animator, overrides.Idle or defaults.Idle)
	local walk = loadTrack(animator, overrides.Walk or defaults.Walk)
	local run = loadTrack(animator, overrides.Run or defaults.Run)
	if idle then
		idle:Play()
	end

	local moving = false
	table.insert(
		npc.Connections,
		humanoid.Running:Connect(function(speed)
			if speed <= 0.75 then
				if moving then
					moving = false
					if walk then
						walk:Stop(0.2)
					end
					if run then
						run:Stop(0.2)
					end
					if idle then
						idle:Play(0.2)
					end
				end
				return
			end
			if not moving then
				moving = true
				if idle then
					idle:Stop(0.2)
				end
				if walk then
					walk:Play(0.2)
				end
				if run then
					run:Play(0.2)
				end
			end
			local heightScale = math.max(humanoid.HipHeight / 2, 0.1)
			local runSpeed = speed / 16 * 1.25 / heightScale
			local walkWeight, runWeight, walkRate, runRate = 1, 0.0001, runSpeed / 0.5, runSpeed
			if runSpeed >= 1 then
				walkWeight, runWeight = 0.0001, 1
			elseif runSpeed > 0.5 then
				local fade = (runSpeed - 0.5) / 0.5
				walkWeight, runWeight, walkRate, runRate = 1 - fade, fade, 1, 1
			end
			if walk then
				walk:AdjustWeight(walkWeight)
				walk:AdjustSpeed(walkRate)
			end
			if run then
				run:AdjustWeight(runWeight)
				run:AdjustSpeed(runRate)
			end
		end)
	)
end

local function despawn(npc: NPC)
	npc.Active = false
	for _, connection in npc.Connections do
		connection:Disconnect()
	end
	table.clear(npc.Connections)
	if npcs[npc.Id] == npc then
		npcs[npc.Id] = nil
	end
	npc.Model:Destroy()
end

-- NPC caiu do mapa, morreu ou foi apagado por algum script: some e reaparece em casa
local function onLost(npc: NPC)
	if not npc.Active then
		return
	end
	despawn(npc)
	warn(`[NPCService] {npc.Id} foi removido inesperadamente; reaparece em {RESPAWN_DELAY}s`)
	task.delay(RESPAWN_DELAY, function()
		if roundActive and not npcs[npc.Id] then
			NPCService.Spawn(npc.Id, npc.Rng:NextInteger(1, 1_000_000_000))
		end
	end)
end

function NPCService.Spawn(residentId: string, seed: number)
	local cfg = CharacterConfig.ById[residentId]
	local template = cfg and getTemplate(cfg)
	if not cfg or not template or npcs[residentId] or not roundActive then
		return
	end
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		warn(`[NPCService] modelo de {residentId} sem Humanoid/HumanoidRootPart`)
		model:Destroy()
		return
	end

	local rng = Random.new(seed)
	local routine = RoutineConfig.Types[cfg.RoutineType] or RoutineConfig.Types.Caseiro
	local npc: NPC = {
		Id = residentId,
		Config = cfg,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Path = PathfindingService:CreatePath(AGENT),
		Planner = RoutinePlanner.new(
			routine,
			{ Home = cfg.HomeId, Work = cfg.WorkPoi, Neighbors = neighborsOf[residentId] },
			cfg.Personality,
			GameConfig.NPCReturnHomeTime,
			rng
		),
		Rng = rng,
		State = "Idle",
		CurrentPoi = cfg.HomeId,
		PausedUntil = 0,
		Active = true,
		Connections = {},
	}

	CharacterService.SetupResident(model, cfg)
	CharacterService.ApplyCollisionGroup(model)
	model:PivotTo(CFrame.new(MapService.GetStandPoint(cfg.HomeId, rng)))
	model.Parent = residentsFolder
	-- física do NPC sempre no servidor: evita trancos quando um jogador chega perto
	pcall(root.SetNetworkOwner, root, nil)
	npcs[residentId] = npc

	setupAnimations(npc)
	table.insert(npc.Connections, humanoid.Died:Connect(function()
		onLost(npc)
	end))
	table.insert(npc.Connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			onLost(npc)
		end
	end))
	task.spawn(runBrain, npc)
end

-- Um jogador puxou conversa: o NPC para, vira para ele e retoma a rotina depois
function NPCService.Interrupt(residentId: string, lookAt: Vector3, seconds: number)
	local npc = npcs[residentId]
	if not npc or not npc.Active then
		return
	end
	npc.PausedUntil = os.clock() + seconds
	local root = npc.Root
	npc.Humanoid:MoveTo(root.Position)
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(lookAt.X, root.Position.Y, lookAt.Z))
end

function NPCService.GetModel(residentId: string): Model?
	local npc = npcs[residentId]
	return if npc then npc.Model else nil
end

function NPCService.BeginRound(timeLeft: () -> number)
	roundActive = true
	getTimeLeft = timeLeft
end

function NPCService.DespawnAll()
	roundActive = false
	for _, npc in npcs do
		despawn(npc)
	end
	table.clear(npcs)
end

return NPCService
