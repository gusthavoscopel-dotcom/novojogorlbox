--!strict
-- "Cérebro" de rotina do NPC: escolhe o próximo destino a partir da rotina, da personalidade e
-- do contexto. Lógica pura (o movimento fica no NPCService), então é testável fora do Studio.
--
-- Comportamento imperfeito, mas coerente:
--   * segue a sequência da rotina em loop, começando de um passo sorteado;
--   * com VariationChance (maior para quem é menos pontual) troca o passo por uma alternativa;
--   * nunca escolhe o lugar onde já está;
--   * às vezes hesita alguns segundos antes de sair (PauseChance);
--   * no fim da rodada volta para casa e fica lá.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local RoutineConfig = require(ReplicatedStorage.Shared.Config.RoutineConfig)

type Rng = Types.Rng

export type Places = {
	Home: string,
	Work: string?,
	Neighbors: { string }, -- casas de outros moradores (destino "Neighbor")
}

export type Personality = { Punctuality: number, Energy: number }

export type Activity = {
	PoiId: string,
	Step: string, -- passo da rotina que gerou o destino ("Home", "Work", "Neighbor", "Praca"...)
	State: string, -- estado ao chegar: "Idle" | "Working" | "Shopping"
	Duration: number,
	Delay: number, -- hesitação antes de sair
	IsHome: boolean,
}

export type Context = {
	TimeLeft: number,
	CurrentPoi: string?,
}

export type Planner = {
	Next: (Context) -> Activity,
}

local RoutinePlanner = {}

function RoutinePlanner.new(
	routine: RoutineConfig.Routine,
	places: Places,
	personality: Personality,
	returnHomeTime: number,
	rng: Rng
): Planner
	local sequence = routine.Sequence
	local index = rng:NextInteger(1, #sequence)

	-- chaves ordenadas para o sorteio ser reproduzível com a mesma seed
	local alternatives: { string } = {}
	local totalWeight = 0
	for step, weight in routine.Alternatives do
		table.insert(alternatives, step)
		totalWeight += weight
	end
	table.sort(alternatives)

	local function between(min: number, max: number): number
		return min + (max - min) * rng:NextNumber()
	end

	local function pickAlternative(): string?
		if totalWeight <= 0 then
			return nil
		end
		local roll = rng:NextNumber() * totalWeight
		for _, step in alternatives do
			roll -= routine.Alternatives[step]
			if roll <= 0 then
				return step
			end
		end
		return alternatives[#alternatives]
	end

	local function resolve(step: string): string
		if step == "Home" then
			return places.Home
		elseif step == "Work" then
			return places.Work or places.Home
		elseif step == "Neighbor" then
			if #places.Neighbors == 0 then
				return places.Home
			end
			return places.Neighbors[rng:NextInteger(1, #places.Neighbors)]
		end
		return step
	end

	local function takeStep(): string
		local step = sequence[index]
		index = index % #sequence + 1
		local chance = routine.VariationChance * (1.5 - personality.Punctuality)
		if rng:NextNumber() < chance then
			return pickAlternative() or step
		end
		return step
	end

	local function duration(step: string): number
		local range = routine.Durations[step] or routine.Durations.Default or { 8, 15 }
		-- quem tem mais energia fica menos tempo parado
		return between(range[1], range[2]) * (1.3 - 0.6 * personality.Energy)
	end

	local function nextActivity(ctx: Context): Activity
		if ctx.TimeLeft <= returnHomeTime then
			return {
				PoiId = places.Home,
				Step = "Home",
				State = "Idle",
				Duration = math.max(ctx.TimeLeft, 0) + 5,
				Delay = 0,
				IsHome = true,
			}
		end

		local step, poi = "Home", places.Home
		for _ = 1, #sequence + 2 do
			step = takeStep()
			poi = resolve(step)
			if poi ~= ctx.CurrentPoi then
				break
			end
		end
		if poi == ctx.CurrentPoi then
			-- rotina sem saída (ex.: sequência de um lugar só): qualquer destino diferente serve
			for _, alternative in alternatives do
				local candidate = resolve(alternative)
				if candidate ~= ctx.CurrentPoi then
					step, poi = alternative, candidate
					break
				end
			end
		end

		return {
			PoiId = poi,
			Step = step,
			State = RoutineConfig.StateByStep[step] or "Idle",
			Duration = duration(step),
			Delay = if rng:NextNumber() < routine.PauseChance then between(1.5, 5) else 0,
			IsHome = poi == places.Home,
		}
	end

	return { Next = nextActivity }
end

return RoutinePlanner
