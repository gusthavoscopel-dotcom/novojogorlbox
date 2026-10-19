--!strict
-- Todas as ações de jogo chegam por ProximityPrompts criados pelo servidor. Antes de qualquer
-- efeito, valida: limite de frequência, fase da partida, se o jogador participa, se está vivo e
-- se está perto do objeto. Atributos dos prompts não podem ser alterados pelo cliente.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MissionService = require(script.Parent.MissionService)
local NPCService = require(script.Parent.NPCService)
local RoundService = require(script.Parent.RoundService)

type Actor = {
	Player: Player,
	ResidentId: string,
	Position: Vector3,
}

local InteractionService = {}

local TALK_PAUSE = 4 -- segundos que o NPC fica parado conversando

local lastUse: { [Player]: number } = {}
local lastTalk: { [Player]: { [string]: number } } = {}

local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function greeting(residentId: string): string
	local cfg = CharacterConfig.ById[residentId]
	local pool = (cfg and cfg.DialoguePool or CharacterConfig.DefaultDialogue).Greeting
	return pool[math.random(1, #pool)]
end

local handlers: { [string]: (Actor, ProximityPrompt) -> () } = {
	-- Qualquer morador responde com uma fala do personagem, seja NPC ou jogador disfarçado:
	-- a diferença tem que aparecer no comportamento, não na resposta automática.
	Talk = function(actor, prompt)
		local targetId = prompt:GetAttribute("ResidentId")
		if typeof(targetId) ~= "string" or targetId == actor.ResidentId then
			return
		end
		local target = RoundService.GetResident(targetId)
		local me = RoundService.GetResident(actor.ResidentId)
		if not target or not me then
			return
		end
		local talks = lastTalk[actor.Player] or {}
		lastTalk[actor.Player] = talks
		local now = os.clock()
		if now - (talks[targetId] or -math.huge) < GameConfig.TalkCooldownPerTarget then
			return
		end
		talks[targetId] = now

		Remotes.Notify:FireClient(actor.Player, "Dialogue", greeting(targetId), target.Name)
		if target.Player then
			Remotes.Notify:FireClient(target.Player, "Info", `{me.Name} puxou conversa com você.`)
		else
			NPCService.Interrupt(targetId, actor.Position, TALK_PAUSE)
		end
		MissionService.Report(actor.Player, "Talk", targetId)
	end,

	Search = function(actor, prompt)
		local spotId = prompt:GetAttribute("SpotId")
		if typeof(spotId) == "string" and not MissionService.Report(actor.Player, "Search", spotId) then
			Remotes.Notify:FireClient(actor.Player, "Info", "Nada de interessante aqui.")
		end
	end,

	Pickup = function(actor)
		if MissionService.Report(actor.Player, "Pickup") then
			Remotes.Notify:FireClient(actor.Player, "Info", "Encomenda retirada! Leve até a caixa de correio indicada na missão.")
		else
			Remotes.Notify:FireClient(actor.Player, "Info", "Não há nenhuma encomenda no seu nome.")
		end
	end,

	Deliver = function(actor, prompt)
		local houseId = prompt:GetAttribute("HouseId")
		if typeof(houseId) == "string" and not MissionService.Report(actor.Player, "Deliver", houseId) then
			Remotes.Notify:FireClient(actor.Player, "Info", "Você não tem encomenda para esta casa.")
		end
	end,
}

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	local action = prompt:GetAttribute("Action")
	local handler = if typeof(action) == "string" then handlers[action] else nil
	if not handler then
		return
	end

	local now = os.clock()
	if now - (lastUse[player] or -math.huge) < GameConfig.InteractionCooldown then
		return
	end
	lastUse[player] = now

	if RoundService.GetPhase() ~= "Playing" then
		return
	end
	local residentId = RoundService.GetResidentIdOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = promptPosition(prompt)
	if not residentId or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") or not target then
		return
	end
	if (root.Position - target).Magnitude > GameConfig.InteractionMaxDistance then
		return
	end

	handler({ Player = player, ResidentId = residentId, Position = root.Position }, prompt)
end

function InteractionService.Start()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		lastTalk[player] = nil
	end)
end

return InteractionService
