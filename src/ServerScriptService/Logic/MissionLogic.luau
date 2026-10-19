--!strict
-- Geração e progresso das missões. Lógica pura e determinística (recebe Rng e o horário atual);
-- o MissionService cuida de jogadores, rede e recompensas.
--
-- Uma missão só avança enquanto está "Active". Ao concluir, falhar ou ser cancelada ela congela,
-- o que impede conclusão dupla e recompensa duplicada.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local MissionConfig = require(ReplicatedStorage.Shared.Config.MissionConfig)

type Rng = Types.Rng
type Template = MissionConfig.Template

export type Named = { Id: string, Name: string }
export type SpotRef = { Id: string, Area: string }

export type Context = {
	Role: string,
	Count: number,
	Pool: { string }?, -- MissionPool do morador (nil = todos os modelos)
	SelfResident: string,
	Home: string,
	Residents: { Named }, -- moradores ativos na partida
	PublicPois: { Named },
	Houses: { Named },
	Spots: { SpotRef },
	Now: number,
}

export type Mission = {
	Id: string,
	TemplateId: string,
	Type: string,
	Title: string,
	Description: string,
	Reward: number,
	FailText: string,
	Status: Types.MissionStatus,
	Progress: number,
	Goal: number,
	ExpiresAt: number?,
	Targets: { string }, -- Visit: POIs | Talk: moradores | Deliver: casa | Find: esconderijo (segredo) | Follow: morador
	TargetNames: { string },
	Done: { [string]: boolean },
	Carrying: boolean,
	Radius: number,
	ResidentTargets: { string }, -- moradores cuja saída do jogo cancela a missão
}

local MissionLogic = {}

local function pickDistinct<T>(pool: { T }, count: number, rng: Rng): { T }
	local copy = table.clone(pool)
	local result: { T } = {}
	for _ = 1, math.min(count, #copy) do
		table.insert(result, table.remove(copy, rng:NextInteger(1, #copy)) :: T)
	end
	return result
end

local function joinNames(names: { string }): string
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " e " .. names[#names]
end

local function fill(text: string, values: { [string]: string }): string
	return (text:gsub("{(%w+)}", values))
end

local function except(list: { Named }, excludedId: string): { Named }
	local result: { Named } = {}
	for _, item in list do
		if item.Id ~= excludedId then
			table.insert(result, item)
		end
	end
	return result
end

local function setTargets(mission: Mission, picked: { Named })
	for _, item in picked do
		table.insert(mission.Targets, item.Id)
		table.insert(mission.TargetNames, item.Name)
	end
end

-- Cada construtor preenche os alvos da missão; retorna false se não há alvos possíveis
local builders: { [string]: (Mission, Template, Context, Rng) -> boolean } = {
	Visit = function(mission, template, ctx, rng)
		local pool = if template.PoiKind == "House" then except(ctx.Houses, ctx.Home) else ctx.PublicPois
		local picked = pickDistinct(pool, template.Count or 3, rng)
		if #picked == 0 then
			return false
		end
		setTargets(mission, picked)
		mission.Goal = #picked
		mission.Description = fill(template.Description, { targets = joinNames(mission.TargetNames) })
		return true
	end,

	Talk = function(mission, template, ctx, rng)
		local picked = pickDistinct(except(ctx.Residents, ctx.SelfResident), template.Count or 2, rng)
		if #picked == 0 then
			return false
		end
		setTargets(mission, picked)
		mission.ResidentTargets = table.clone(mission.Targets)
		mission.Goal = #picked
		mission.Description = fill(template.Description, { targets = joinNames(mission.TargetNames) })
		return true
	end,

	Deliver = function(mission, template, ctx, rng)
		local house = pickDistinct(except(ctx.Houses, ctx.Home), 1, rng)[1]
		if not house then
			return false
		end
		setTargets(mission, { house })
		mission.Goal = 2 -- retirar + entregar
		mission.Description = fill(template.Description, { target = house.Name })
		return true
	end,

	Find = function(mission, template, ctx, rng)
		local spot = pickDistinct(ctx.Spots, 1, rng)[1]
		if not spot then
			return false
		end
		-- o esconderijo exato fica só no servidor; o jogador recebe apenas a área
		table.insert(mission.Targets, spot.Id)
		table.insert(mission.TargetNames, spot.Area)
		local items = template.Items or { "um objeto" }
		mission.Description = fill(template.Description, {
			item = items[rng:NextInteger(1, #items)],
			area = spot.Area,
		})
		return true
	end,

	Follow = function(mission, template, ctx, rng)
		local target = pickDistinct(except(ctx.Residents, ctx.SelfResident), 1, rng)[1]
		if not target then
			return false
		end
		setTargets(mission, { target })
		mission.ResidentTargets = { target.Id }
		mission.Goal = template.Seconds or 25
		mission.Description = fill(template.Description, {
			target = target.Name,
			seconds = tostring(mission.Goal),
			radius = tostring(mission.Radius),
		})
		return true
	end,
}

MissionLogic.SupportedTypes = builders

local function newMission(template: Template, index: number, now: number): Mission
	return {
		Id = template.Id .. "#" .. index,
		TemplateId = template.Id,
		Type = template.Type,
		Title = template.Title,
		Description = template.Description,
		Reward = template.Reward,
		FailText = template.FailText,
		Status = "Active",
		Progress = 0,
		Goal = 1,
		ExpiresAt = if template.TimeLimit then now + template.TimeLimit else nil,
		Targets = {},
		TargetNames = {},
		Done = {},
		Carrying = false,
		Radius = template.Radius or 0,
		ResidentTargets = {},
	}
end

local function pickWeightedIndex(candidates: { Template }, rng: Rng): number
	local total = 0
	for _, template in candidates do
		total += template.Weight
	end
	local roll = rng:NextNumber() * total
	for i, template in candidates do
		roll -= template.Weight
		if roll <= 0 then
			return i
		end
	end
	return #candidates
end

-- Sorteia ctx.Count missões de modelos diferentes, filtradas por papel e pelo MissionPool
function MissionLogic.Generate(templates: { Template }, ctx: Context, rng: Rng): { Mission }
	local pool = ctx.Pool
	local candidates: { Template } = {}
	for _, template in templates do
		local roleAllowed = table.find(template.AllowedRoles, ctx.Role) ~= nil
		local inPool = pool == nil or table.find(pool, template.Id) ~= nil
		if roleAllowed and inPool then
			table.insert(candidates, template)
		end
	end

	local missions: { Mission } = {}
	while #missions < ctx.Count and #candidates > 0 do
		local template = table.remove(candidates, pickWeightedIndex(candidates, rng)) :: Template
		local mission = newMission(template, #missions + 1, ctx.Now)
		local build = builders[template.Type]
		if build and build(mission, template, ctx, rng) then
			table.insert(missions, mission)
		end
	end
	return missions
end

local function markTarget(mission: Mission, targetId: string?): boolean
	if targetId == nil or mission.Done[targetId] or table.find(mission.Targets, targetId) == nil then
		return false
	end
	mission.Done[targetId] = true
	mission.Progress += 1
	if mission.Progress >= mission.Goal then
		mission.Status = "Completed"
	end
	return true
end

-- Eventos: "EnterPoi" (POI), "Talk" (morador), "Search" (esconderijo), "Pickup", "Deliver" (casa).
-- Retorna true se a missão mudou.
function MissionLogic.Apply(mission: Mission, event: string, targetId: string?): boolean
	if mission.Status ~= "Active" then
		return false
	end
	local kind = mission.Type
	if
		(kind == "Visit" and event == "EnterPoi")
		or (kind == "Talk" and event == "Talk")
		or (kind == "Find" and event == "Search")
	then
		return markTarget(mission, targetId)
	end
	if kind == "Deliver" then
		if event == "Pickup" and not mission.Carrying and mission.Progress == 0 then
			mission.Carrying = true
			mission.Progress = 1
			return true
		elseif event == "Deliver" and mission.Carrying and targetId == mission.Targets[1] then
			mission.Carrying = false
			mission.Progress = 2
			mission.Status = "Completed"
			return true
		end
	end
	return false
end

-- Missão "Follow": soma o tempo em que o jogador ficou dentro do raio do alvo.
-- distance = nil quando o alvo não está no mapa. Retorna true quando vale a pena atualizar o cliente.
function MissionLogic.TickFollow(mission: Mission, dt: number, distance: number?): boolean
	if mission.Status ~= "Active" or mission.Type ~= "Follow" or distance == nil or distance > mission.Radius then
		return false
	end
	local before = math.floor(mission.Progress)
	mission.Progress = math.min(mission.Goal, mission.Progress + dt)
	if mission.Progress >= mission.Goal then
		mission.Status = "Completed"
		return true
	end
	return math.floor(mission.Progress) ~= before
end

function MissionLogic.Expire(mission: Mission, now: number): boolean
	local expiresAt = mission.ExpiresAt
	if mission.Status == "Active" and expiresAt ~= nil and now >= expiresAt then
		mission.Status = "Failed"
		return true
	end
	return false
end

-- Morador-alvo saiu do jogo: cancela, a não ser que aquele alvo já tenha sido cumprido
function MissionLogic.CancelIfTarget(mission: Mission, residentId: string): boolean
	if mission.Status ~= "Active" or mission.Done[residentId] or table.find(mission.ResidentTargets, residentId) == nil then
		return false
	end
	mission.Status = "Cancelled"
	return true
end

-- Fim da rodada: o que não foi concluído falha
function MissionLogic.Finish(mission: Mission): boolean
	if mission.Status == "Active" then
		mission.Status = "Failed"
		return true
	end
	return false
end

function MissionLogic.View(mission: Mission): Types.MissionView
	local progressText
	if mission.Type == "Deliver" then
		if mission.Status == "Completed" then
			progressText = "Entregue!"
		elseif mission.Carrying then
			progressText = "Leve até: " .. mission.TargetNames[1]
		else
			progressText = "Retire no balcão de encomendas do Mercado"
		end
	elseif mission.Type == "Follow" then
		progressText = string.format("%d/%d s", math.floor(mission.Progress), mission.Goal)
	else
		progressText = string.format("%d/%d", mission.Progress, mission.Goal)
	end

	return {
		Id = mission.Id,
		Title = mission.Title,
		Description = mission.Description,
		Status = mission.Status,
		ProgressText = progressText,
		Progress = mission.Progress,
		Goal = mission.Goal,
		Reward = mission.Reward,
		ExpiresAt = mission.ExpiresAt,
		FailText = mission.FailText,
	}
end

return MissionLogic
