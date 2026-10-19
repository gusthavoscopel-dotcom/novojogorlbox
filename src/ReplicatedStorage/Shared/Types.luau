--!strict
-- Tipos compartilhados entre servidor e cliente (formato dos dados que passam pelos remotes).

-- A lógica pura só usa rng:NextInteger(min, max) e rng:NextNumber(); os testes passam um
-- gerador falso com esses dois métodos.
export type Rng = Random

export type MissionStatus = "Active" | "Completed" | "Failed" | "Cancelled"

export type MissionView = {
	Id: string,
	Title: string,
	Description: string,
	Status: MissionStatus,
	ProgressText: string,
	Progress: number,
	Goal: number,
	Reward: number,
	ExpiresAt: number?, -- em workspace:GetServerTimeNow()
	FailText: string,
}

export type PlayerState = {
	InRound: boolean,
	ResidentId: string?,
	ResidentName: string?,
}

export type RevealEntry = {
	ResidentName: string,
	PlayerName: string?, -- nil = era NPC
}

export type RoundResult = {
	Reason: string,
	Participated: boolean,
	Won: boolean,
	ResidentName: string?,
	Missions: { MissionView },
	Earned: number,
	Breakdown: { { Label: string, Amount: number } },
	Reveal: { RevealEntry },
}

return {}
