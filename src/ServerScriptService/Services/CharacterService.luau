--!strict
-- Aparência dos moradores e ciclo de vida dos personagens dos jogadores.
-- O mesmo HumanoidDescription vira o NPC e o disfarce do jogador, e SetupResident aplica nome,
-- velocidade e o prompt "Conversar" de forma idêntica nos dois: nada visual denuncia quem é NPC.
-- CharacterAutoLoads fica desligado; o servidor decide onde cada um nasce (lobby ou bairro).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfig = require(ReplicatedStorage.Shared.Config.CharacterConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

type Character = CharacterConfig.Character

local CharacterService = {}

-- moradores não colidem entre si: ninguém bloqueia porta ou empurra NPC, e o comportamento
-- físico é igual para jogadores e NPCs
local COLLISION_GROUP = "Residents"

local descriptions: { [string]: HumanoidDescription } = {}
local respawnHandler: (Player) -> () = function(player)
	CharacterService.SpawnInLobby(player)
end
local warnedRigType = false

function CharacterService.GetDescription(cfg: Character): HumanoidDescription
	local cached = descriptions[cfg.CharacterId]
	if cached then
		return cached
	end
	local description = Instance.new("HumanoidDescription")
	local look = cfg.Appearance
	description.HeadColor = look.SkinColor
	description.TorsoColor = look.ShirtColor
	description.LeftArmColor = look.ArmColor or look.SkinColor
	description.RightArmColor = look.ArmColor or look.SkinColor
	description.LeftLegColor = look.PantsColor
	description.RightLegColor = look.PantsColor
	for property, value in look.Description do
		local ok, err = pcall(function()
			(description :: any)[property] = value
		end)
		if not ok then
			warn(`[CharacterService] {cfg.CharacterId}: Appearance.Description.{property} inválida: {err}`)
		end
	end
	descriptions[cfg.CharacterId] = description
	return description
end

function CharacterService.ApplyCollisionGroup(model: Model)
	local function apply(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = COLLISION_GROUP
		end
	end
	for _, descendant in model:GetDescendants() do
		apply(descendant)
	end
	model.DescendantAdded:Connect(apply)
end

-- Comum a NPCs e jogadores disfarçados
function CharacterService.SetupResident(model: Model, cfg: Character)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		warn(`[CharacterService] modelo de {cfg.CharacterId} sem Humanoid/HumanoidRootPart`)
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 and not warnedRigType then
		warnedRigType = true
		warn("[CharacterService] Personagem não é R15. Em Game Settings > Avatar, use Avatar Type = R15 para jogadores e NPCs ficarem iguais.")
	end
	humanoid.DisplayName = cfg.DisplayName
	humanoid.WalkSpeed = cfg.WalkSpeed

	local talk = Instance.new("ProximityPrompt")
	talk.Name = "TalkPrompt"
	talk.ActionText = "Conversar"
	talk.ObjectText = cfg.DisplayName
	talk.MaxActivationDistance = 8
	talk.RequiresLineOfSight = false
	talk:SetAttribute("Action", "Talk")
	talk:SetAttribute("ResidentId", cfg.CharacterId)
	talk.Parent = root
end

function CharacterService.SpawnInLobby(player: Player)
	if not player.Parent then
		return
	end
	local ok, err = pcall(player.LoadCharacterAsync, player)
	if not ok then
		warn(`[CharacterService] falha ao criar personagem de {player.Name}: {err}`)
	end
end

function CharacterService.SpawnAsResident(player: Player, cfg: Character, cframe: CFrame)
	if not player.Parent then
		return
	end
	-- com StreamingEnabled, carrega o chão antes de teleportar para ninguém cair do mapa
	pcall(player.RequestStreamAroundAsync, player, cframe.Position, 5)
	local ok, err = pcall(player.LoadCharacterWithHumanoidDescriptionAsync, player, CharacterService.GetDescription(cfg):Clone())
	local character = player.Character
	if not ok or not character then
		warn(`[CharacterService] falha ao disfarçar {player.Name} como {cfg.CharacterId}: {err}`)
		return
	end
	character:PivotTo(cframe)
	CharacterService.SetupResident(character, cfg)
end

-- RoundService decide se o jogador volta ao bairro (disfarçado) ou ao lobby
function CharacterService.SetRespawnHandler(handler: (Player) -> ())
	respawnHandler = handler
end

local function onCharacterAdded(player: Player, character: Model)
	CharacterService.ApplyCollisionGroup(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Once(function()
		task.wait(GameConfig.RespawnDelay)
		-- só renasce se nada já tiver criado um personagem novo nesse meio tempo
		if player.Parent and player.Character == character then
			respawnHandler(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	else
		respawnHandler(player)
	end
end

function CharacterService.Start()
	Players.CharacterAutoLoads = false
	if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return CharacterService
