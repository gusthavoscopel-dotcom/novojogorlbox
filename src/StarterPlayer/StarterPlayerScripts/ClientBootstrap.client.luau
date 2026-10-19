--!strict
-- Ponto de entrada do cliente: liga os controllers (que conectam os eventos) e só então pede ao
-- servidor o estado atual, para não perder nenhuma atualização enviada nesse meio tempo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Controllers = script.Parent:WaitForChild("Controllers")
local UIController = require(Controllers:WaitForChild("UIController"))
local MissionController = require(Controllers:WaitForChild("MissionController"))
local InteractionController = require(Controllers:WaitForChild("InteractionController"))

local steps: { { Name: string, Start: () -> () } } = {
	{ Name = "UIController", Start = UIController.Start },
	{ Name = "MissionController", Start = MissionController.Start },
	{ Name = "InteractionController", Start = InteractionController.Start },
}
for _, step in steps do
	local ok, err = pcall(step.Start :: any)
	if not ok then
		warn(`[Cliente] falha ao iniciar {step.Name}: {err}`)
	end
end

local ok, snapshot = pcall(function()
	return Remotes.GetPlayerState:InvokeServer()
end)
if ok and type(snapshot) == "table" then
	UIController.ApplyPlayerState(snapshot.State)
	MissionController.ApplyMissions(snapshot.Missions)
end
