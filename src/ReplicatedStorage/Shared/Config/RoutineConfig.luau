--!strict
-- Rotinas dos NPCs. Cada passo da sequência é um destino:
--   "Home" = casa do morador, "Work" = CharacterConfig.WorkPoi, "Neighbor" = casa de outro morador,
--   ou o Id de um ponto público do MapConfig (Praca, Mercado, Lanchonete, Parque, PontoOnibus).
-- O NPC segue a sequência em loop; com VariationChance (ajustada pela pontualidade) troca o passo
-- por uma alternativa ponderada. PauseChance cria pequenos atrasos antes de sair.

export type Routine = {
	Sequence: { string },
	Alternatives: { [string]: number }, -- destino -> peso
	VariationChance: number,
	PauseChance: number,
	Durations: { [string]: { number } }, -- {mín, máx} em segundos; "Default" para os demais
}

-- Estado da máquina de estados enquanto o NPC está no destino
local StateByStep: { [string]: string } = {
	Home = "Idle",
	Work = "Working",
	Mercado = "Shopping",
	Lanchonete = "Shopping",
}

local Types: { [string]: Routine } = {
	Caseiro = {
		Sequence = { "Home", "Mercado", "Home", "Praca", "Home", "Neighbor" },
		Alternatives = { Praca = 3, Mercado = 2, Neighbor = 2, Parque = 1 },
		VariationChance = 0.2,
		PauseChance = 0.35,
		Durations = { Home = { 15, 30 }, Default = { 8, 16 } },
	},
	Trabalhador = {
		Sequence = { "Work", "Work", "Lanchonete", "Work", "Praca", "Home" },
		Alternatives = { Lanchonete = 2, Praca = 2, Mercado = 1 },
		VariationChance = 0.15,
		PauseChance = 0.15,
		Durations = { Work = { 20, 35 }, Home = { 10, 20 }, Default = { 8, 14 } },
	},
	Passeador = {
		Sequence = { "Parque", "Praca", "PontoOnibus", "Parque", "Lanchonete", "Home" },
		Alternatives = { Parque = 3, Praca = 3, PontoOnibus = 1, Neighbor = 1 },
		VariationChance = 0.3,
		PauseChance = 0.25,
		Durations = { Parque = { 14, 26 }, Default = { 8, 16 } },
	},
	Social = {
		Sequence = { "Praca", "Neighbor", "Lanchonete", "Praca", "Neighbor", "Home" },
		Alternatives = { Neighbor = 3, Praca = 3, Mercado = 1, Lanchonete = 1 },
		VariationChance = 0.3,
		PauseChance = 0.3,
		Durations = { Neighbor = { 10, 20 }, Default = { 8, 16 } },
	},
	Imprevisivel = {
		Sequence = { "Praca", "Mercado", "Parque", "Neighbor", "PontoOnibus", "Home" },
		Alternatives = { Praca = 2, Mercado = 2, Parque = 2, Lanchonete = 2, PontoOnibus = 2, Neighbor = 2 },
		VariationChance = 0.5,
		PauseChance = 0.4,
		Durations = { Default = { 5, 14 } },
	},
}

return {
	Types = Types,
	StateByStep = StateByStep,
}
