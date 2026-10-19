--!strict
-- Regras gerais da partida. Altere aqui sem mexer na lógica.

local GameConfig = {
	-- Jogadores
	MinPlayers = 1, -- 1 permite testar sozinho; para o jogo publicado use 3 ou mais
	MaxParticipants = 10, -- jogadores por partida (os demais esperam no lobby)

	-- Tempos (segundos)
	IntermissionTime = 15,
	RoundDuration = 420, -- 7 minutos (recomendado entre 360 e 480)
	ResultsTime = 15,
	RespawnDelay = 3,

	-- Moradores (jogadores disfarçados + NPCs)
	TargetResidents = 10, -- total desejado de moradores no bairro
	MinNPCs = 4,
	MaxActiveNPCs = 10, -- limite de NPCs ativos ao mesmo tempo
	NPCReturnHomeTime = 45, -- nos últimos N segundos os NPCs voltam para casa
	NPCNearPlayerDistance = 120, -- NPCs mais longe que isso de qualquer jogador atualizam com menos frequência

	-- Missões
	MissionsPerPlayer = 3,

	-- Recompensas em Fichas do Bairro (concedidas só no fim da rodada)
	ParticipationReward = 10,
	AllMissionsBonus = 25,
	MaxGrantPerRound = 500, -- trava de segurança do EconomyService

	-- Interações (validadas no servidor)
	InteractionMaxDistance = 12,
	InteractionCooldown = 0.4,
	TalkCooldownPerTarget = 6,

	-- Debug: defina um número para repetir exatamente a mesma partida
	FixedSeed = nil :: number?,
}

return GameConfig
