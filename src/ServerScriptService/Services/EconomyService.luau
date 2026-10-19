--!strict
-- Fichas do Bairro. Fase 1: saldo em memória, exibido no leaderstats.
-- Nenhum remote deixa o cliente mexer em fichas: só o servidor chama Grant.
-- A Fase 4 troca o armazenamento por DataStoreService mantendo esta mesma interface.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local EconomyService = {}

-- chaves já pagas por jogador (ex.: "round:3"), para nunca pagar a mesma recompensa duas vezes
local grantedKeys: { [Player]: { [string]: boolean } } = {}

local function fichasValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Fichas")
	return if value and value:IsA("IntValue") then value else nil
end

local function setup(player: Player)
	if grantedKeys[player] then
		return
	end
	grantedKeys[player] = {}
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local fichas = Instance.new("IntValue")
	fichas.Name = "Fichas"
	fichas.Parent = stats
	stats.Parent = player
end

-- Concede fichas uma única vez por chave. Retorna false se o pagamento foi recusado.
function EconomyService.Grant(player: Player, amount: number, key: string): boolean
	if amount ~= math.floor(amount) or amount <= 0 or amount > GameConfig.MaxGrantPerRound then
		warn(`[EconomyService] valor inválido recusado: {amount} ({key})`)
		return false
	end
	local keys = grantedKeys[player]
	local value = fichasValue(player)
	if not keys or not value or keys[key] then
		return false
	end
	keys[key] = true
	value.Value += amount
	return true
end

function EconomyService.Start()
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		grantedKeys[player] = nil
	end)
end

return EconomyService
