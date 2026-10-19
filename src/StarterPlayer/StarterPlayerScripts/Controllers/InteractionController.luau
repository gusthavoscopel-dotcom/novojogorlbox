--!strict
-- Ajustes locais de interação:
--  * esconde o "Conversar" do próprio personagem (o servidor coloca o prompt em todo morador,
--    jogador ou NPC, para que a presença do prompt não denuncie ninguém);
--  * desliga o botão de reset: um morador que "morre" do nada seria uma pista injusta.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local InteractionController = {}

local function hideOwnTalkPrompt(character: Model)
	local function check(instance: Instance)
		if instance:IsA("ProximityPrompt") and instance.Name == "TalkPrompt" then
			instance.Enabled = false -- só neste cliente; os outros continuam vendo
		end
	end
	for _, descendant in character:GetDescendants() do
		check(descendant)
	end
	character.DescendantAdded:Connect(check)
end

function InteractionController.Start()
	local player = Players.LocalPlayer
	if player.Character then
		hideOwnTalkPrompt(player.Character)
	end
	player.CharacterAdded:Connect(hideOwnTalkPrompt)

	-- SetCore só funciona depois que os scripts internos do Roblox carregam
	task.spawn(function()
		for _ = 1, 20 do
			if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false) then
				return
			end
			task.wait(0.5)
		end
	end)
end

return InteractionController
