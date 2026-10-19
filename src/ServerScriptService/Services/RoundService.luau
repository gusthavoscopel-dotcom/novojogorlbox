--!strict
-- Ciclo da partida: Lobby -> Intermission -> Preparing -> Playing -> Results -> Lobby.
-- É a única fonte de verdade sobre quem participa e quem está disfarçado de qual morador.
-- O estado público (fase e relógio) vai em atributos de ReplicatedStorage.GameState; quem é
-- jogador ou NPC só é revelado na tela de resultado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local MatchSetup = require(script.Parent.Parent.Logic.MatchSetup)
local CharacterService = require(script.Parent.CharacterService)
local EconomyService = require(script.Parent.EconomyService)
local MapService = require(script.Parent.MapService)
local MissionService = require(script.Parent.MissionService)
local NPCService = require(script.Parent.NPCService)

export type Resident = {
	Id: string,
	Name: string,
	Player: Player?, -- nil = NPC (ou jogador que saiu)
	PlayerName: string?, -- guardado para a revelação final
	Present: boolean,
}

type Match = {
	Id: number,
	Residents: { [string]: Resident },
	Order: { string },
	ResidentOf: { [Player]: string }, -- só jogadores que ainda estão na partida
	EndsAt: number, -- os.clock(); 0 enquanto prepara
}

local RoundService = {}

local TICK = 0.5
local REASONS = {
	Timeout = "O tempo acabou!",
	AllDone = "Todas as missões foram resolvidas!",
	Empty = "Todos os jogadores da partida saíram.",
}

local phase = "Lobby"
local match: Match? = nil
local roundCounter = 0
local lastStateRequest: { [Player]: number } = {}

local function setPhase(newPhase: string, duration: number?)
	phase = newPhase
	Remotes.GameState:SetAttribute("Phase", newPhase)
	Remotes.GameState:SetAttribute("PhaseEndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
end

function RoundService.GetPhase(): string
	return phase
end

function RoundService.GetResidentIdOf(player: Player): string?
	local m = match
	return if m then m.ResidentOf[player] else nil
end

-- Morador ativo (presente no bairro), seja jogador ou NPC
function RoundService.GetResident(residentId: string): Resident?
	local m = match
	local resident = m and m.Residents[residentId]
	return if resident and resident.Present then resident else nil
end

local function playerState(player: Player): Types.PlayerState
	local residentId = RoundService.GetResidentIdOf(player)
	local resident = if residentId then RoundService.GetResident(residentId) else nil
	return {
		InRound = resident ~= nil,
		ResidentId = residentId,
		ResidentName = if resident then resident.Name else nil,
	}
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function residentModel(residentId: string): Model?
	local resident = RoundService.GetResident(residentId)
	if not resident then
		return nil
	end
	if resident.Player then
		return resident.Player.Character
	end
	return NPCService.GetModel(residentId)
end

local function distanceTo(player: Player, residentId: string): number?
	local a = rootOf(player.Character)
	local b = rootOf(residentModel(residentId))
	return if a and b then (a.Position - b.Position).Magnitude else nil
end

local function homeCFrame(residentId: string, rng: Random): CFrame
	return CFrame.new(MapService.GetStandPoint(CharacterConfig.ById[residentId].HomeId, rng))
end

local function cleanup(m: Match)
	NPCService.DespawnAll()
	MissionService.Clear()
	if match == m then
		match = nil
	end
	for player in m.ResidentOf do
		if player.Parent then
			Remotes.PlayerState:FireClient(player, playerState(player))
			task.spawn(CharacterService.SpawnInLobby, player)
		end
	end
	setPhase("Lobby")
end

local function finishRound(m: Match, reason: string)
	setPhase("Results", GameConfig.ResultsTime)
	MissionService.FinishRound()

	local reveal: { Types.RevealEntry } = {}
	for _, id in m.Order do
		local resident = m.Residents[id]
		table.insert(reveal, { ResidentName = resident.Name, PlayerName = resident.PlayerName })
	end

	for _, player in Players:GetPlayers() do
		local residentId = m.ResidentOf[player]
		local result: Types.RoundResult = {
			Reason = REASONS[reason] or reason,
			Participated = residentId ~= nil,
			Won = false,
			Missions = {},
			Earned = 0,
			Breakdown = {},
			Reveal = reveal,
		}
		if residentId then
			local summary = MissionService.GetSummary(player)
			local breakdown = { { Label = "Participação", Amount = GameConfig.ParticipationReward } }
			if summary.Reward > 0 then
				table.insert(breakdown, { Label = `Missões concluídas ({summary.Completed})`, Amount = summary.Reward })
			end
			if summary.AllDone then
				table.insert(breakdown, { Label = "Bônus: todas as missões", Amount = GameConfig.AllMissionsBonus })
			end
			local total = 0
			for _, line in breakdown do
				total += line.Amount
			end
			-- a chave da rodada garante pagamento único mesmo se este trecho rodar de novo
			local paid = EconomyService.Grant(player, total, `round:{m.Id}`)
			result.Won = summary.AllDone
			result.ResidentName = m.Residents[residentId].Name
			result.Missions = summary.Views
			result.Earned = if paid then total else 0
			result.Breakdown = breakdown
		end
		Remotes.RoundResult:FireClient(player, result)
	end

	if reason ~= "Empty" then
		task.wait(GameConfig.ResultsTime)
	end
	cleanup(m)
end

local function playLoop(m: Match): string
	local lastPoi: { [Player]: string? } = {}
	while true do
		local dt = task.wait(TICK)
		-- "visitar lugar" é detectado aqui, pela posição, sem confiar no cliente
		for player in m.ResidentOf do
			local root = rootOf(player.Character)
			if root then
				local poi = MapService.GetPoiAt(root.Position)
				if poi and poi ~= lastPoi[player] then
					MissionService.Report(player, "EnterPoi", poi)
				end
				lastPoi[player] = poi
			end
		end
		MissionService.Tick(dt, distanceTo)

		if next(m.ResidentOf) == nil then
			return "Empty"
		elseif os.clock() >= m.EndsAt then
			return "Timeout"
		elseif not MissionService.AnyActive() then
			return "AllDone"
		end
	end
end

local function runRound()
	roundCounter += 1
	local seed = GameConfig.FixedSeed or Random.new():NextInteger(1, 2_000_000_000)
	local rng = Random.new(seed)
	print(`[RoundService] rodada {roundCounter} | seed {seed}`)
	setPhase("Preparing")

	local maxPlayers = MatchSetup.MaxPlayers(#CharacterConfig.List, GameConfig.MaxParticipants, GameConfig.MinNPCs)
	local players = MatchSetup.Shuffle(Players:GetPlayers(), rng)
	while #players > maxPlayers do
		table.remove(players)
	end
	local residentIds = MatchSetup.PickResidents(CharacterConfig.List, #players, GameConfig, rng)
	local residentOf, npcIds = MatchSetup.AssignPlayers(residentIds, players, rng)

	local m: Match = { Id = roundCounter, Residents = {}, Order = residentIds, ResidentOf = residentOf, EndsAt = 0 }
	for _, id in residentIds do
		m.Residents[id] = { Id = id, Name = CharacterConfig.ById[id].DisplayName, Present = true }
	end
	for player, id in residentOf do
		m.Residents[id].Player = player
		m.Residents[id].PlayerName = `{player.DisplayName} (@{player.Name})`
	end
	match = m

	NPCService.BeginRound(function()
		return if m.EndsAt == 0 then GameConfig.RoundDuration else math.max(0, m.EndsAt - os.clock())
	end)
	for i, id in npcIds do
		task.spawn(NPCService.Spawn, id, seed + i)
	end

	-- jogadores nascem disfarçados na porta de casa, igual aos NPCs
	local pending = 0
	for player, id in residentOf do
		pending += 1
		local spawnAt = homeCFrame(id, rng)
		task.spawn(function()
			CharacterService.SpawnAsResident(player, CharacterConfig.ById[id], spawnAt)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 15
	while pending > 0 and os.clock() < deadline do
		task.wait(0.2)
	end

	-- quem saiu durante a preparação não pode virar alvo de missão
	local residentList = {}
	for _, id in residentIds do
		if m.Residents[id].Present then
			table.insert(residentList, { Id = id, Name = m.Residents[id].Name })
		end
	end
	for player, id in residentOf do
		if player.Parent then
			MissionService.Assign(player, id, "Morador", residentList, rng)
			Remotes.PlayerState:FireClient(player, playerState(player))
			Remotes.Notify:FireClient(player, "Info", `Você é {m.Residents[id].Name}! Aja como um morador comum e cumpra suas missões secretas.`, "Seu disfarce")
		end
	end

	m.EndsAt = os.clock() + GameConfig.RoundDuration
	setPhase("Playing", GameConfig.RoundDuration)
	finishRound(m, playLoop(m))
end

local function onPlayerRemoving(player: Player)
	lastStateRequest[player] = nil
	local m = match
	local residentId = if m then m.ResidentOf[player] else nil
	if not m or not residentId then
		return
	end
	local resident = m.Residents[residentId]
	m.ResidentOf[player] = nil
	resident.Present = false
	resident.Player = nil
	resident.PlayerName = (resident.PlayerName or player.Name) .. " (saiu)"
	MissionService.RemovePlayer(player)
	MissionService.CancelTargeting(residentId)
end

local function respawn(player: Player)
	local m = match
	local residentId = if m and (phase == "Playing" or phase == "Preparing") then m.ResidentOf[player] else nil
	if residentId then
		CharacterService.SpawnAsResident(player, CharacterConfig.ById[residentId], homeCFrame(residentId, Random.new()))
	else
		CharacterService.SpawnInLobby(player)
	end
end

local function mainLoop()
	while true do
		setPhase("Lobby")
		while #Players:GetPlayers() < GameConfig.MinPlayers do
			task.wait(1)
		end

		setPhase("Intermission", GameConfig.IntermissionTime)
		local startsAt = os.clock() + GameConfig.IntermissionTime
		local enough = true
		while os.clock() < startsAt do
			if #Players:GetPlayers() < GameConfig.MinPlayers then
				enough = false
				break
			end
			task.wait(0.5)
		end

		if enough then
			local ok, err = pcall(runRound :: any)
			if not ok then
				-- qualquer erro inesperado devolve todos ao lobby e o ciclo recomeça
				warn(`[RoundService] erro na rodada, reiniciando: {err}`)
				local m = match
				if m then
					pcall(cleanup, m)
				else
					NPCService.DespawnAll()
					MissionService.Clear()
				end
			end
		end
	end
end

function RoundService.Start()
	CharacterService.SetRespawnHandler(respawn)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- única chamada cliente -> servidor: somente leitura dos próprios dados, com limite de frequência
	Remotes.GetPlayerState.OnServerInvoke = function(player: Player)
		local now = os.clock()
		if now - (lastStateRequest[player] or -math.huge) < 1 then
			return nil
		end
		lastStateRequest[player] = now
		return { State = playerState(player), Missions = MissionService.GetViews(player) }
	end

	task.spawn(mainLoop)
end

return RoundService
