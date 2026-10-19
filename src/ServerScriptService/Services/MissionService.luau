--!strict
-- Missões secretas de cada jogador: sorteio, progresso, avisos e resumo de recompensa.
-- As regras ficam em Logic/MissionLogic; aqui só ligamos a lógica aos jogadores e à rede.
-- Cada jogador só recebe as próprias missões (FireClient), nunca as dos outros.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local MissionConfig = require(ReplicatedStorage.Shared.Config.MissionConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local MissionLogic = require(script.Parent.Parent.Logic.MissionLogic)

type Mission = MissionLogic.Mission

export type Summary = {
	Views: { Types.MissionView },
	Reward: number,
	Completed: number,
	AllDone: boolean, -- concluiu todas as missões que não foram canceladas
}

local MissionService = {}

local missionsByPlayer: { [Player]: { Mission } } = {}

-- Alvos fixos do mapa, montados uma vez
local publicPois: { MissionLogic.Named } = {}
local houses: { MissionLogic.Named } = {}
for _, poi in MapConfig.Pois do
	table.insert(if poi.Kind == "House" then houses else publicPois, { Id = poi.Id, Name = poi.DisplayName })
end
local spots: { MissionLogic.SpotRef } = {}
for _, spot in MapConfig.Spots do
	table.insert(spots, { Id = spot.Id, Area = spot.Area })
end

local function missionsOf(player: Player): { Mission }
	return missionsByPlayer[player] or {}
end

function MissionService.GetViews(player: Player): { Types.MissionView }
	local views = {}
	for _, mission in missionsOf(player) do
		table.insert(views, MissionLogic.View(mission))
	end
	return views
end

local function push(player: Player)
	if player.Parent then
		Remotes.MissionUpdate:FireClient(player, MissionService.GetViews(player))
	end
end

local function announce(player: Player, mission: Mission)
	if mission.Status == "Completed" then
		Remotes.Notify:FireClient(player, "Success", `Missão concluída: {mission.Title} (+{mission.Reward} fichas no fim da rodada)`)
	elseif mission.Status == "Failed" then
		Remotes.Notify:FireClient(player, "Warning", `Missão falhou: {mission.Title}`)
	elseif mission.Status == "Cancelled" then
		Remotes.Notify:FireClient(player, "Info", `Missão cancelada (o morador-alvo saiu do jogo): {mission.Title}`)
	end
end

-- residents: moradores ativos na partida (jogadores e NPCs, sem distinção)
function MissionService.Assign(player: Player, residentId: string, role: string, residents: { MissionLogic.Named }, rng: Random)
	local cfg = CharacterConfig.ById[residentId]
	missionsByPlayer[player] = MissionLogic.Generate(MissionConfig.Templates, {
		Role = role,
		Count = GameConfig.MissionsPerPlayer,
		Pool = cfg.MissionPool,
		SelfResident = residentId,
		Home = cfg.HomeId,
		Residents = residents,
		PublicPois = publicPois,
		Houses = houses,
		Spots = spots,
		Now = workspace:GetServerTimeNow(),
	}, rng)
	push(player)
end

-- Evento validado pelo servidor. Retorna true se alguma missão do jogador avançou.
function MissionService.Report(player: Player, event: string, targetId: string?): boolean
	local consumed = false
	for _, mission in missionsOf(player) do
		if MissionLogic.Apply(mission, event, targetId) then
			consumed = true
			announce(player, mission)
		end
	end
	if consumed then
		push(player)
	end
	return consumed
end

-- Chamado a cada meio segundo pelo RoundService: prazos e missões de seguir alguém.
-- distanceTo(player, residentId) devolve a distância atual até o morador (nil se ele sumiu).
function MissionService.Tick(dt: number, distanceTo: (Player, string) -> number?)
	local now = workspace:GetServerTimeNow()
	for player, missions in missionsByPlayer do
		local changed = false
		for _, mission in missions do
			local updated = MissionLogic.Expire(mission, now)
			if not updated and mission.Type == "Follow" and mission.Status == "Active" then
				updated = MissionLogic.TickFollow(mission, dt, distanceTo(player, mission.Targets[1]))
			end
			if updated then
				changed = true
				announce(player, mission)
			end
		end
		if changed then
			push(player)
		end
	end
end

function MissionService.CancelTargeting(residentId: string)
	for player, missions in missionsByPlayer do
		local changed = false
		for _, mission in missions do
			if MissionLogic.CancelIfTarget(mission, residentId) then
				changed = true
				announce(player, mission)
			end
		end
		if changed then
			push(player)
		end
	end
end

function MissionService.AnyActive(): boolean
	for _, missions in missionsByPlayer do
		for _, mission in missions do
			if mission.Status == "Active" then
				return true
			end
		end
	end
	return false
end

-- Fim da rodada: o que ficou aberto falha (sem aviso individual; aparece no resultado)
function MissionService.FinishRound()
	for player, missions in missionsByPlayer do
		for _, mission in missions do
			MissionLogic.Finish(mission)
		end
		push(player)
	end
end

function MissionService.GetSummary(player: Player): Summary
	local reward, completed, counted = 0, 0, 0
	for _, mission in missionsOf(player) do
		if mission.Status == "Completed" then
			reward += mission.Reward
			completed += 1
		end
		if mission.Status ~= "Cancelled" then
			counted += 1
		end
	end
	return {
		Views = MissionService.GetViews(player),
		Reward = reward,
		Completed = completed,
		AllDone = counted > 0 and completed == counted,
	}
end

function MissionService.RemovePlayer(player: Player)
	missionsByPlayer[player] = nil
end

function MissionService.Clear()
	for player in missionsByPlayer do
		if player.Parent then
			Remotes.MissionUpdate:FireClient(player, {})
		end
	end
	table.clear(missionsByPlayer)
end

return MissionService
