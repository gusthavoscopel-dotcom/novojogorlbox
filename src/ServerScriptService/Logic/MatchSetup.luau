--!strict
-- Sorteios do início da partida (quem participa, quais moradores existem, quem é NPC).
-- Lógica pura: não usa APIs do Roblox, então roda nos testes fora do Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local Types = require(ReplicatedStorage.Shared.Types)

type Rng = Types.Rng

export type Limits = { TargetResidents: number, MinNPCs: number, MaxActiveNPCs: number }

local MatchSetup = {}

function MatchSetup.Shuffle<T>(list: { T }, rng: Rng): { T }
	local result = table.clone(list)
	for i = #result, 2, -1 do
		local j = rng:NextInteger(1, i)
		result[i], result[j] = result[j], result[i]
	end
	return result
end

-- Quantos jogadores cabem numa partida sem faltar moradores para o mínimo de NPCs
function MatchSetup.MaxPlayers(characterCount: number, maxParticipants: number, minNPCs: number): number
	return math.max(0, math.min(maxParticipants, characterCount - minNPCs))
end

-- Moradores ativos da partida: os principais sempre entram; os secundários são sorteados
function MatchSetup.PickResidents(characters: { CharacterConfig.Character }, playerCount: number, limits: Limits, rng: Rng): { string }
	local npcCount = math.clamp(limits.TargetResidents - playerCount, limits.MinNPCs, limits.MaxActiveNPCs)
	local total = math.min(#characters, playerCount + npcCount)

	local mains: { string } = {}
	local others: { string } = {}
	for _, character in characters do
		table.insert(if character.IsMain then mains else others, character.CharacterId)
	end

	local ordered = MatchSetup.Shuffle(mains, rng)
	for _, id in MatchSetup.Shuffle(others, rng) do
		table.insert(ordered, id)
	end

	local picked: { string } = {}
	for i = 1, total do
		picked[i] = ordered[i]
	end
	return picked
end

-- Cada jogador recebe um morador diferente; os moradores que sobram viram NPCs
function MatchSetup.AssignPlayers<P>(residentIds: { string }, players: { P }, rng: Rng): ({ [P]: string }, { string })
	assert(#players <= #residentIds, "mais jogadores do que moradores disponíveis")
	local shuffled = MatchSetup.Shuffle(residentIds, rng)
	local byPlayer: { [P]: string } = {}
	local npcs: { string } = {}
	for i, residentId in shuffled do
		local player = players[i]
		if player ~= nil then
			byPlayer[player] = residentId
		else
			table.insert(npcs, residentId)
		end
	end
	return byPlayer, npcs
end

return MatchSetup
