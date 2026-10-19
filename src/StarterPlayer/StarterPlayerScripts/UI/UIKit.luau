--!strict
-- Peças de interface reutilizáveis: tema, criadores tipados e escala automática para telas pequenas.
-- Cada painel recebe o próprio UIScale (UIKit.scaled), assim fundos de tela cheia não encolhem.

local Players = game:GetService("Players")

local UIKit = {}

UIKit.Theme = {
	Panel = Color3.fromRGB(255, 249, 237),
	PanelAlt = Color3.fromRGB(255, 238, 209),
	Track = Color3.fromRGB(232, 222, 202),
	Ink = Color3.fromRGB(45, 42, 62),
	InkSoft = Color3.fromRGB(110, 106, 130),
	Accent = Color3.fromRGB(255, 133, 64),
	Success = Color3.fromRGB(38, 186, 153),
	Danger = Color3.fromRGB(232, 72, 85),
	Info = Color3.fromRGB(72, 149, 239),
	White = Color3.new(1, 1, 1),
	Font = Enum.Font.BuilderSans,
	FontBold = Enum.Font.BuilderSansBold,
	FontTitle = Enum.Font.FredokaOne,
}

-- Referência de layout: 1100x620. Celular fica em ~0.75 para o texto continuar legível.
local MIN_SCALE, MAX_SCALE = 0.75, 1.2
local scales: { UIScale } = {}
local hookedCamera: Camera? = nil

local function refreshScales()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local value = math.clamp(math.min(viewport.X / 1100, viewport.Y / 620), MIN_SCALE, MAX_SCALE)
	for _, scale in scales do
		scale.Scale = value
	end
end

local function hookCamera()
	local camera = workspace.CurrentCamera
	if camera and camera ~= hookedCamera then
		hookedCamera = camera
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
	end
	refreshScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)

function UIKit.scaled(target: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Parent = target
	table.insert(scales, scale)
	hookCamera()
end

function UIKit.isSmallScreen(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y < 500
end

function UIKit.screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false -- o jogador renasce ao entrar/sair da partida
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UIKit.frame(parent: Instance, name: string, size: UDim2, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.BorderSizePixel = 0
	if color then
		frame.BackgroundColor3 = color
	else
		frame.BackgroundTransparency = 1
	end
	frame.Parent = parent
	return frame
end

-- Texto com quebra de linha que cresce na vertical; RichText ligado (use UIKit.escape em textos externos)
function UIKit.label(parent: Instance, text: string, textSize: number, font: Enum.Font?, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = font or UIKit.Theme.Font
	label.TextSize = textSize
	label.TextColor3 = color or UIKit.Theme.Ink
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	label.Text = text
	label.Parent = parent
	return label
end

function UIKit.button(parent: Instance, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = color
	button.AutoButtonColor = true -- escurece ao passar o mouse/tocar
	button.Font = UIKit.Theme.FontBold
	button.TextSize = 18
	button.TextColor3 = UIKit.Theme.White
	button.Text = text
	button.Parent = parent
	UIKit.corner(button, 10)
	return button
end

function UIKit.corner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function UIKit.stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIKit.padding(parent: Instance, pixels: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
end

function UIKit.list(parent: Instance, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, spacing)
	layout.Parent = parent
	return layout
end

function UIKit.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function UIKit.hex(color: Color3): string
	return "#" .. color:ToHex()
end

function UIKit.formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return UIKit
