--!strict
-- HUD principal: fase e relógio, status do lobby, disfarce atual, avisos, falas dos moradores
-- e tela de resultado. Só apresenta o que o servidor manda; não decide nada do jogo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local UIKit = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("UIKit"))

local Theme = UIKit.Theme

local UIController = {}

local PHASE_TITLES: { [string]: string } = {
	Lobby = "LOBBY",
	Intermission = "PREPARE-SE",
	Preparing = "PREPARANDO O BAIRRO",
	Playing = "PARTIDA EM ANDAMENTO",
	Results = "FIM DE RODADA",
}
local NOTIFY_COLORS: { [string]: Color3 } = {
	Info = Theme.Info,
	Success = Theme.Success,
	Warning = Theme.Danger,
}
local STATUS_ICONS: { [string]: string } = {
	Completed = "✅",
	Failed = "❌",
	Cancelled = "➖",
	Active = "⏳",
}
local MAX_TOASTS = 4
local TOAST_TIME = 5
local DIALOGUE_TIME = 5

local inRound = false
local residentName: string? = nil
local toastCount = 0
local dialogueToken = 0

---------------------------------------------------------------------------
-- Construção
---------------------------------------------------------------------------

local hud = UIKit.screen("MainUI", 1)

local topBar = UIKit.frame(hud, "TopBar", UDim2.fromOffset(400, 66), Theme.Panel)
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.new(0.5, 0, 0, 8)
UIKit.corner(topBar, 16)
UIKit.stroke(topBar, Theme.Ink, 2)
UIKit.scaled(topBar)

local phaseLabel = UIKit.label(topBar, "", 14, Theme.FontBold, Theme.Accent)
phaseLabel.AutomaticSize = Enum.AutomaticSize.None
phaseLabel.Position = UDim2.fromOffset(16, 8)
phaseLabel.Size = UDim2.new(1, -130, 0, 16)

local statusLabel = UIKit.label(topBar, "", 16, Theme.Font, Theme.Ink)
statusLabel.AutomaticSize = Enum.AutomaticSize.None
statusLabel.Position = UDim2.fromOffset(16, 25)
statusLabel.Size = UDim2.new(1, -130, 0, 36)
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

local timerLabel = UIKit.label(topBar, "", 32, Theme.FontTitle, Theme.Ink)
timerLabel.AutomaticSize = Enum.AutomaticSize.None
timerLabel.AnchorPoint = Vector2.new(1, 0.5)
timerLabel.Position = UDim2.new(1, -16, 0.5, 0)
timerLabel.Size = UDim2.fromOffset(110, 44)
timerLabel.TextXAlignment = Enum.TextXAlignment.Right

-- filho da barra do topo: escala junto e fica sempre logo abaixo dela
local identityPill = UIKit.frame(topBar, "Disfarce", UDim2.fromOffset(0, 32), Theme.Ink)
identityPill.AutomaticSize = Enum.AutomaticSize.X
identityPill.AnchorPoint = Vector2.new(0.5, 0)
identityPill.Position = UDim2.new(0.5, 0, 1, 8)
identityPill.Visible = false
UIKit.corner(identityPill, 16)
local identityLabel = UIKit.label(identityPill, "", 16, Theme.Font, Theme.White)
identityLabel.AutomaticSize = Enum.AutomaticSize.X
identityLabel.Size = UDim2.fromScale(0, 1)
identityLabel.TextWrapped = false
local identityPadding = Instance.new("UIPadding")
identityPadding.PaddingLeft = UDim.new(0, 14)
identityPadding.PaddingRight = UDim.new(0, 14)
identityPadding.Parent = identityPill

local toastList = UIKit.frame(hud, "Avisos", UDim2.fromOffset(300, 0))
toastList.AnchorPoint = Vector2.new(1, 0)
toastList.Position = UDim2.new(1, -12, 0, 84)
toastList.AutomaticSize = Enum.AutomaticSize.Y
UIKit.list(toastList, 8)
UIKit.scaled(toastList)

local dialogue = UIKit.frame(hud, "Fala", UDim2.fromOffset(460, 0), Theme.Panel)
dialogue.AnchorPoint = Vector2.new(0.5, 1)
dialogue.Position = UDim2.new(0.5, 0, 1, -24)
dialogue.AutomaticSize = Enum.AutomaticSize.Y
dialogue.Visible = false
UIKit.corner(dialogue, 14)
UIKit.stroke(dialogue, Theme.Accent, 3)
UIKit.padding(dialogue, 12)
UIKit.list(dialogue, 4)
UIKit.scaled(dialogue)
local speakerLabel = UIKit.label(dialogue, "", 18, Theme.FontTitle, Theme.Accent)
local lineLabel = UIKit.label(dialogue, "", 18, Theme.Font, Theme.Ink)
lineLabel.LayoutOrder = 1

-- Resultado: ScreenGui separado com fundo escurecido
local resultsGui = UIKit.screen("ResultsUI", 10)
resultsGui.Enabled = false
local backdrop = UIKit.frame(resultsGui, "Fundo", UDim2.fromScale(1, 1), Color3.new(0, 0, 0))
backdrop.BackgroundTransparency = 0.45

local card = UIKit.frame(resultsGui, "Cartao", UDim2.fromOffset(520, 470), Theme.Panel)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
UIKit.corner(card, 20)
UIKit.stroke(card, Theme.Ink, 3)
UIKit.scaled(card)

local resultTitle = UIKit.label(card, "", 34, Theme.FontTitle, Theme.Accent)
resultTitle.AutomaticSize = Enum.AutomaticSize.None
resultTitle.Size = UDim2.new(1, -40, 0, 44)
resultTitle.Position = UDim2.fromOffset(20, 14)
resultTitle.TextXAlignment = Enum.TextXAlignment.Center

local resultBody = Instance.new("ScrollingFrame")
resultBody.Name = "Conteudo"
resultBody.BackgroundTransparency = 1
resultBody.BorderSizePixel = 0
resultBody.Position = UDim2.fromOffset(20, 64)
resultBody.Size = UDim2.new(1, -40, 1, -128)
resultBody.CanvasSize = UDim2.new()
resultBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
resultBody.ScrollBarThickness = 6
resultBody.ScrollBarImageColor3 = Theme.InkSoft
resultBody.Parent = card
UIKit.list(resultBody, 6)

local closeButton = UIKit.button(card, "Fechar", Theme.Accent)
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -14)
closeButton.Size = UDim2.fromOffset(180, 42)
closeButton.Activated:Connect(function()
	resultsGui.Enabled = false
end)

---------------------------------------------------------------------------
-- Comportamento
---------------------------------------------------------------------------

local function statusText(phase: string, remaining: number): string
	if phase == "Lobby" then
		local count = #Players:GetPlayers()
		if count < GameConfig.MinPlayers then
			return `Aguardando jogadores ({count}/{GameConfig.MinPlayers})`
		end
		return "Preparando a próxima partida..."
	elseif phase == "Intermission" then
		return `A partida começa em {math.max(0, math.ceil(remaining))}s`
	elseif phase == "Preparing" then
		return "Distribuindo disfarces..."
	elseif phase == "Playing" then
		if inRound then
			return "Cumpra suas missões sem chamar atenção!"
		end
		return "Partida em andamento. Você entra na próxima!"
	end
	return "Veja quem era quem!"
end

local function refresh()
	local phase = (Remotes.GameState:GetAttribute("Phase") :: string?) or "Lobby"
	local endsAt = (Remotes.GameState:GetAttribute("PhaseEndsAt") :: number?) or 0
	local remaining = if endsAt > 0 then endsAt - workspace:GetServerTimeNow() else 0
	phaseLabel.Text = PHASE_TITLES[phase] or phase
	statusLabel.Text = statusText(phase, remaining)
	timerLabel.Text = if endsAt > 0 then UIKit.formatTime(remaining) else ""
	timerLabel.TextColor3 = if phase == "Playing" and remaining <= 30 then Theme.Danger else Theme.Ink
	identityPill.Visible = inRound and residentName ~= nil
	if phase == "Lobby" and resultsGui.Enabled then
		resultsGui.Enabled = false
	end
end

local function fadeIn(card: Frame, label: TextLabel, stroke: UIStroke)
	card.BackgroundTransparency = 1
	label.TextTransparency = 1
	stroke.Transparency = 1
	local info = TweenInfo.new(0.25)
	TweenService:Create(card, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(label, info, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, info, { Transparency = 0 }):Play()
end

local function toast(kind: string, text: string, title: string?)
	toastCount += 1
	local color = NOTIFY_COLORS[kind] or Theme.Info
	local toastCard = UIKit.frame(toastList, "Aviso", UDim2.fromScale(1, 0), Theme.Panel)
	toastCard.AutomaticSize = Enum.AutomaticSize.Y
	toastCard.LayoutOrder = -toastCount -- o mais novo fica em cima
	UIKit.corner(toastCard, 12)
	UIKit.padding(toastCard, 10)
	local stroke = UIKit.stroke(toastCard, color, 2)
	local body = UIKit.escape(text)
	local label = UIKit.label(toastCard, if title then `<b>{UIKit.escape(title)}</b>\n{body}` else body, 16, Theme.Font, Theme.Ink)
	fadeIn(toastCard, label, stroke)

	local cards = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = MAX_TOASTS + 1, #cards do
		cards[i]:Destroy()
	end

	task.delay(TOAST_TIME, function()
		if toastCard.Parent then
			toastCard:Destroy()
		end
	end)
end

local function showDialogue(speaker: string, line: string)
	dialogueToken += 1
	local token = dialogueToken
	speakerLabel.Text = UIKit.escape(speaker)
	lineLabel.Text = `“{UIKit.escape(line)}”`
	dialogue.Visible = true
	task.delay(DIALOGUE_TIME, function()
		if token == dialogueToken then
			dialogue.Visible = false
		end
	end)
end

local function section(title: string, order: number): number
	local label = UIKit.label(resultBody, `<b>{title}</b>`, 18, Theme.FontBold, Theme.Accent)
	label.LayoutOrder = order
	return order + 1
end

local function line(text: string, order: number, color: Color3?): number
	local label = UIKit.label(resultBody, text, 16, Theme.Font, color or Theme.Ink)
	label.LayoutOrder = order
	return order + 1
end

local function showResult(result: Types.RoundResult)
	for _, child in resultBody:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	resultTitle.Text = if result.Participated and result.Won then "VITÓRIA!" else "FIM DE RODADA"
	resultTitle.TextColor3 = if result.Participated and result.Won then Theme.Success else Theme.Accent

	local order = line(UIKit.escape(result.Reason), 1, Theme.InkSoft)
	if result.Participated then
		order = line(`Você era <b>{UIKit.escape(result.ResidentName or "?")}</b>.`, order)
		order = section("Suas missões", order)
		for _, mission in result.Missions do
			order = line(`{STATUS_ICONS[mission.Status] or "•"} {UIKit.escape(mission.Title)}`, order)
		end
		order = section(`+{result.Earned} Fichas do Bairro`, order)
		for _, entry in result.Breakdown do
			order = line(`{UIKit.escape(entry.Label)}: +{entry.Amount}`, order, Theme.InkSoft)
		end
	else
		order = line("Você assistiu do lobby. Entre na próxima partida!", order)
	end

	order = section("Quem era quem?", order)
	for _, entry in result.Reveal do
		local who = if entry.PlayerName
			then `<font color="{UIKit.hex(Theme.Info)}">Jogador: {UIKit.escape(entry.PlayerName)}</font>`
			else `<font color="{UIKit.hex(Theme.InkSoft)}">NPC 🤖</font>`
		order = line(`<b>{UIKit.escape(entry.ResidentName)}</b> — {who}`, order)
	end

	resultBody.CanvasPosition = Vector2.zero
	resultsGui.Enabled = true
end

function UIController.ApplyPlayerState(state: Types.PlayerState)
	inRound = state.InRound
	residentName = state.ResidentName
	identityLabel.Text = if state.ResidentName then `Seu disfarce: <b>{UIKit.escape(state.ResidentName)}</b>` else ""
	refresh()
end

function UIController.Start()
	Remotes.Notify.OnClientEvent:Connect(function(kind: string, text: string, title: string?)
		if kind == "Dialogue" then
			showDialogue(title or "", text)
		else
			toast(kind, text, title)
		end
	end)
	Remotes.PlayerState.OnClientEvent:Connect(UIController.ApplyPlayerState)
	Remotes.RoundResult.OnClientEvent:Connect(showResult)

	task.spawn(function()
		while true do
			refresh()
			task.wait(0.25)
		end
	end)
end

return UIController
