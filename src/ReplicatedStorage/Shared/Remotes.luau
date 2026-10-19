--!strict
-- Ponto único de acesso à rede. O servidor cria os remotes; o cliente espera por eles.
-- Só existe um remote cliente -> servidor (GetPlayerState, somente leitura). Todas as ações de
-- jogo passam por ProximityPrompts, validados no InteractionService.
--
-- Servidor -> cliente:
--   Notify(kind, text, title?)       kind: "Info" | "Success" | "Warning" | "Dialogue"
--   PlayerState(state)               dados privados do jogador (quem ele é na rodada)
--   MissionUpdate(missions)          missões privadas do jogador
--   RoundResult(result)              resultado e revelação no fim da rodada
-- Estado público da partida fica em atributos de ReplicatedStorage.GameState:
--   Phase ("Lobby" | "Intermission" | "Preparing" | "Playing" | "Results"), PhaseEndsAt (GetServerTimeNow)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local function get(parent: Instance, name: string, className: string): Instance
	if IS_SERVER then
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = parent
		return created
	end
	return parent:WaitForChild(name)
end

local folder = get(ReplicatedStorage, "Remotes", "Folder")

return {
	Notify = get(folder, "Notify", "RemoteEvent") :: RemoteEvent,
	PlayerState = get(folder, "PlayerState", "RemoteEvent") :: RemoteEvent,
	MissionUpdate = get(folder, "MissionUpdate", "RemoteEvent") :: RemoteEvent,
	RoundResult = get(folder, "RoundResult", "RemoteEvent") :: RemoteEvent,
	GetPlayerState = get(folder, "GetPlayerState", "RemoteFunction") :: RemoteFunction,
	GameState = get(ReplicatedStorage, "GameState", "Folder") :: Folder,
}
