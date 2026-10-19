--!strict
-- Painel das missões secretas. O servidor envia só as missões deste jogador, já com textos e
-- progresso calculados; aqui apenas desenhamos. Em telas pequenas começa recolhido.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local Theme = UIKit.Theme

local MissionController = {}

local STATUS_STYLE: { [string]: { Color: Color3, Icon: string, Text: string } } = {
	Active = { Color = Theme.Accent, Icon = "⏳", Text = "em andamento" },
	Completed = { Color = Theme.Success, Icon = "✅", Text = "concluída" },
	Failed = { Color = Theme.Danger, Icon = "❌", Text = "falhou" },
	Cancelled = { Color = Theme.InkSoft, Icon = "➖", Text = "cancelada" },
}

local missions: { Types.MissionView } = {}
local countdowns: { { Label: TextLabel, Text: string, ExpiresAt: number } } = {}
local collapsed = UIKit.isSmallScreen()

local gui = UIKit.screen("MissionUI", 2)

local panel = UIKit.frame(gui, "Painel", UDim2.fromOffset(300, 0), Theme.Panel)
panel.Position = UDim2.fromOffset(12, 84)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Visible = false
UIKit.corner(panel, 14)
UIKit.stroke(panel, Theme.Ink, 2)
UIKit.padding(panel, 10)
UIKit.list(panel, 8)
UIKit.scaled(panel)

local header = UIKit.button(panel, "", Theme.Ink)
header.Size = UDim2.new(1, 0, 0, 34)
header.TextSize = 17
header.TextXAlignment = Enum.TextXAlignment.Left
local headerPadding = Instance.new("UIPadding")
headerPadding.PaddingLeft = UDim.new(0, 10)
headerPadding.Parent = header

local list = UIKit.frame(panel, "Lista", UDim2.fromScale(1, 0))
list.LayoutOrder = 1
list.AutomaticSize = Enum.AutomaticSize.Y
UIKit.list(list, 8)

local function updateHeader()
	local done = 0
	for _, mission in missions do
		if mission.Status == "Completed" then
			done += 1
		end
	end
	header.Text = `📋 Missões secretas  {done}/{#missions}   {if collapsed then "▸" else "▾"}`
	list.Visible = not collapsed
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(countdowns)

	for index, mission in missions do
		local style = STATUS_STYLE[mission.Status] or STATUS_STYLE.Active
		local card = UIKit.frame(list, mission.Id, UDim2.fromScale(1, 0), Theme.PanelAlt)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.LayoutOrder = index
		UIKit.corner(card, 10)
		UIKit.padding(card, 8)
		UIKit.list(card, 4)

		local title = UIKit.label(
			card,
			`{style.Icon} <b>{UIKit.escape(mission.Title)}</b>  <font color="{UIKit.hex(Theme.Success)}">+{mission.Reward}</font>`,
			17,
			Theme.Font,
			Theme.Ink
		)
		title.LayoutOrder = 1
		UIKit.label(card, UIKit.escape(mission.Description), 15, Theme.Font, Theme.Ink).LayoutOrder = 2

		local track = UIKit.frame(card, "Barra", UDim2.new(1, 0, 0, 8), Theme.Track)
		track.LayoutOrder = 3
		UIKit.corner(track, 4)
		local fill = UIKit.frame(track, "Progresso", UDim2.fromScale(math.clamp(mission.Progress / math.max(mission.Goal, 1), 0, 1), 1), style.Color)
		UIKit.corner(fill, 4)

		local statusText = `{UIKit.escape(mission.ProgressText)} · {style.Text}`
		local status = UIKit.label(card, statusText, 14, Theme.FontBold, style.Color)
		status.LayoutOrder = 4
		local expiresAt = mission.ExpiresAt
		if mission.Status == "Active" and expiresAt then
			table.insert(countdowns, { Label = status, Text = statusText, ExpiresAt = expiresAt })
		end
		if mission.Status == "Active" then
			UIKit.label(card, UIKit.escape(mission.FailText), 13, Theme.Font, Theme.InkSoft).LayoutOrder = 5
		end
	end

	updateHeader()
	panel.Visible = #missions > 0
end

function MissionController.ApplyMissions(views: { Types.MissionView })
	missions = views
	render()
end

function MissionController.Start()
	header.Activated:Connect(function()
		collapsed = not collapsed
		updateHeader()
	end)
	Remotes.MissionUpdate.OnClientEvent:Connect(MissionController.ApplyMissions)

	-- prazo das missões com tempo limite (o servidor é quem realmente decide a falha)
	task.spawn(function()
		while true do
			local now = workspace:GetServerTimeNow()
			for _, countdown in countdowns do
				countdown.Label.Text = `{countdown.Text} · ⏱ {UIKit.formatTime(countdown.ExpiresAt - now)}`
			end
			task.wait(0.5)
		end
	end)
end

return MissionController
