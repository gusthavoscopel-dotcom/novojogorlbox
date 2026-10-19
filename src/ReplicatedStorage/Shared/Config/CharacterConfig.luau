--!strict
-- Moradores do bairro. Cada campo é independente: aparência (Appearance), personalidade
-- (Personality), rotina (RoutineType -> RoutineConfig), falas (DialoguePool) e missões (MissionPool).
--
-- APARÊNCIA PROVISÓRIA: os quatro personagens principais usam pele amarela clássica do Roblox
-- e cores de roupa distintas só até as imagens de referência chegarem. Para aplicar a aparência
-- real, preencha Appearance (cores) e Appearance.Description com IDs do catálogo, por exemplo:
--   Description = { Shirt = 123, Pants = 456, HairAccessory = "789,1011", Face = 1213 }
-- Qualquer propriedade de HumanoidDescription vale (escalas, acessórios, partes do corpo).
-- O mesmo HumanoidDescription é usado no NPC e no jogador disfarçado, então os dois ficam iguais.
--
-- SuspicionTraits são etiquetas de comportamento que a Fase 2 usa para gerar pistas.

export type Personality = {
	Sociability: number, -- 0..1 (Fase 2: puxa conversa)
	Curiosity: number, -- 0..1 (Fase 2: investiga eventos)
	Punctuality: number, -- 0..1: quanto segue a sequência da rotina
	Energy: number, -- 0..1: quanto tempo fica parado em cada lugar
}

export type Appearance = {
	SkinColor: Color3,
	ShirtColor: Color3, -- tronco
	PantsColor: Color3, -- pernas
	ArmColor: Color3?, -- nil = cor da pele (manga curta)
	Description: { [string]: any },
}

export type Character = {
	CharacterId: string,
	DisplayName: string,
	ModelName: string,
	IsMain: boolean,
	HomeId: string,
	WorkPoi: string?,
	WalkSpeed: number,
	Personality: Personality,
	RoutineType: string,
	DialoguePool: { Greeting: { string } }?,
	SuspicionTraits: { string },
	MissionPool: { string }?, -- nil = todas as missões permitidas
	AnimationConfig: { [string]: string }, -- sobrescreve AssetConfig.Animations só neste NPC
	Appearance: Appearance,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PLACEHOLDER_SKIN = rgb(245, 205, 48)

local list: { Character } = {
	-- Personagens principais (PLACEHOLDER até receber as referências visuais)
	{
		CharacterId = "Yuri22",
		DisplayName = "Yuri22",
		ModelName = "Yuri22",
		IsMain = true,
		HomeId = "CasaYuri22",
		WalkSpeed = 13,
		Personality = { Sociability = 0.7, Curiosity = 0.8, Punctuality = 0.35, Energy = 0.9 },
		RoutineType = "Imprevisivel",
		DialoguePool = {
			Greeting = {
				"Opa! Eu ia pro Mercado... ou era pra Praça? Enfim, oi!",
				"E aí, vizinho! Tudo tranquilo por aqui?",
				"Psiu... tô de olho em uns moradores meio estranhos.",
			},
		},
		SuspicionTraits = { "MudaDeIdeia", "ParaDeRepente" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = PLACEHOLDER_SKIN,
			ShirtColor = rgb(214, 48, 49),
			PantsColor = rgb(45, 52, 54),
			Description = {},
		},
	},
	{
		CharacterId = "Dona",
		DisplayName = "Dona",
		ModelName = "Dona",
		IsMain = true,
		HomeId = "CasaDona",
		WalkSpeed = 11,
		Personality = { Sociability = 0.9, Curiosity = 0.9, Punctuality = 0.6, Energy = 0.6 },
		RoutineType = "Social",
		DialoguePool = {
			Greeting = {
				"Ai, que susto! Chega de mansinho assim não!",
				"Eu vi tudo, viu? Tu-do!",
				"Bom dia, vizinho! Já regou as plantas hoje?",
			},
		},
		SuspicionTraits = { "ObservaOsOutros", "VisitaVizinhos" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = PLACEHOLDER_SKIN,
			ShirtColor = rgb(142, 68, 173),
			PantsColor = rgb(52, 73, 94),
			ArmColor = rgb(142, 68, 173),
			Description = {},
		},
	},
	{
		CharacterId = "Muriloso",
		DisplayName = "Muriloso",
		ModelName = "Muriloso",
		IsMain = true,
		HomeId = "CasaMuriloso",
		WalkSpeed = 11,
		Personality = { Sociability = 0.8, Curiosity = 0.5, Punctuality = 0.5, Energy = 0.4 },
		RoutineType = "Passeador",
		DialoguePool = {
			Greeting = {
				"Fala, vizinho! Dia bonito pra não fazer nada, né?",
				"Relaxa, aqui no bairro tudo se resolve.",
				"Opa, beleza? Tô indo ali e já volto.",
			},
		},
		SuspicionTraits = { "FicaMuitoTempo", "AndaSemPressa" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = PLACEHOLDER_SKIN,
			ShirtColor = rgb(39, 174, 96),
			PantsColor = rgb(160, 140, 100),
			Description = {},
		},
	},
	{
		CharacterId = "TioSam",
		DisplayName = "Tio Sam",
		ModelName = "TioSam",
		IsMain = true,
		HomeId = "CasaTioSam",
		WorkPoi = "Mercado",
		WalkSpeed = 12,
		Personality = { Sociability = 0.6, Curiosity = 0.4, Punctuality = 0.9, Energy = 0.7 },
		RoutineType = "Trabalhador",
		DialoguePool = {
			-- Falas provisórias: troque pelas falas características reais do personagem.
			Greeting = {
				"Ô, sobrinho! Chegou na hora certa.",
				"No meu tempo o bairro era bem mais calmo...",
				"Tenho tarefa pra fazer, mas antes: bom dia!",
			},
		},
		SuspicionTraits = { "RotinaFixa", "HorarioCerto" },
		MissionPool = { "Entrega", "Papo", "Passeio", "Achados" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = PLACEHOLDER_SKIN,
			ShirtColor = rgb(41, 128, 185),
			PantsColor = rgb(236, 240, 241),
			ArmColor = rgb(41, 128, 185),
			Description = {},
		},
	},

	-- Moradores secundários (fictícios)
	{
		CharacterId = "SeuZe",
		DisplayName = "Seu Zé",
		ModelName = "SeuZe",
		IsMain = false,
		HomeId = "CasaAmarela",
		WalkSpeed = 10,
		Personality = { Sociability = 0.5, Curiosity = 0.6, Punctuality = 0.85, Energy = 0.3 },
		RoutineType = "Caseiro",
		SuspicionTraits = { "RotinaFixa", "FicaMuitoTempo" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(234, 184, 146),
			ShirtColor = rgb(230, 126, 34),
			PantsColor = rgb(93, 64, 55),
			Description = {},
		},
	},
	{
		CharacterId = "VoNena",
		DisplayName = "Vó Nena",
		ModelName = "VoNena",
		IsMain = false,
		HomeId = "CasaAmarela",
		WalkSpeed = 10,
		Personality = { Sociability = 0.7, Curiosity = 0.7, Punctuality = 0.9, Energy = 0.25 },
		RoutineType = "Caseiro",
		SuspicionTraits = { "RotinaFixa", "AndaSemPressa" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(141, 85, 36),
			ShirtColor = rgb(232, 67, 147),
			PantsColor = rgb(99, 110, 114),
			ArmColor = rgb(232, 67, 147),
			Description = {},
		},
	},
	{
		CharacterId = "DonaCida",
		DisplayName = "Dona Cida",
		ModelName = "DonaCida",
		IsMain = false,
		HomeId = "CasaVerde",
		WalkSpeed = 10,
		Personality = { Sociability = 0.95, Curiosity = 0.85, Punctuality = 0.55, Energy = 0.5 },
		RoutineType = "Social",
		SuspicionTraits = { "VisitaVizinhos", "ObservaOsOutros" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(198, 134, 66),
			ShirtColor = rgb(253, 203, 110),
			PantsColor = rgb(108, 92, 231),
			Description = {},
		},
	},
	{
		CharacterId = "Bia",
		DisplayName = "Bia",
		ModelName = "Bia",
		IsMain = false,
		HomeId = "CasaAzul",
		WalkSpeed = 13,
		Personality = { Sociability = 0.5, Curiosity = 0.4, Punctuality = 0.7, Energy = 0.95 },
		RoutineType = "Passeador",
		SuspicionTraits = { "SempreComPressa" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(255, 220, 177),
			ShirtColor = rgb(0, 206, 201),
			PantsColor = rgb(45, 52, 54),
			Description = {},
		},
	},
	{
		CharacterId = "Rafa",
		DisplayName = "Rafa",
		ModelName = "Rafa",
		IsMain = false,
		HomeId = "CasaAzul",
		WalkSpeed = 12,
		Personality = { Sociability = 0.6, Curiosity = 0.6, Punctuality = 0.5, Energy = 0.7 },
		RoutineType = "Passeador",
		SuspicionTraits = { "ParaParaObservar" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(224, 172, 105),
			ShirtColor = rgb(9, 132, 227),
			PantsColor = rgb(178, 190, 195),
			Description = {},
		},
	},
	{
		CharacterId = "Carlinhos",
		DisplayName = "Carlinhos",
		ModelName = "Carlinhos",
		IsMain = false,
		HomeId = "CasaRosa",
		WalkSpeed = 14,
		Personality = { Sociability = 0.8, Curiosity = 0.95, Punctuality = 0.2, Energy = 1 },
		RoutineType = "Imprevisivel",
		SuspicionTraits = { "MudaDeIdeia", "SempreComPressa" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(255, 205, 148),
			ShirtColor = rgb(225, 112, 85),
			PantsColor = rgb(9, 132, 227),
			Description = { HeightScale = 0.9 },
		},
	},
	{
		CharacterId = "Lucia",
		DisplayName = "Lúcia",
		ModelName = "Lucia",
		IsMain = false,
		HomeId = "CasaRosa",
		WorkPoi = "Mercado",
		WalkSpeed = 12,
		Personality = { Sociability = 0.6, Curiosity = 0.3, Punctuality = 0.95, Energy = 0.6 },
		RoutineType = "Trabalhador",
		SuspicionTraits = { "RotinaFixa", "HorarioCerto" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(141, 85, 36),
			ShirtColor = rgb(214, 48, 49),
			PantsColor = rgb(45, 52, 54),
			ArmColor = rgb(214, 48, 49),
			Description = {},
		},
	},
	{
		CharacterId = "Jorginho",
		DisplayName = "Jorginho",
		ModelName = "Jorginho",
		IsMain = false,
		HomeId = "CasaLaranja",
		WorkPoi = "Lanchonete",
		WalkSpeed = 11,
		Personality = { Sociability = 0.7, Curiosity = 0.4, Punctuality = 0.8, Energy = 0.5 },
		RoutineType = "Trabalhador",
		SuspicionTraits = { "RotinaFixa", "FicaMuitoTempo" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(234, 184, 146),
			ShirtColor = rgb(255, 255, 255),
			PantsColor = rgb(45, 52, 54),
			ArmColor = rgb(255, 255, 255),
			Description = {},
		},
	},
	{
		CharacterId = "Toninho",
		DisplayName = "Toninho",
		ModelName = "Toninho",
		IsMain = false,
		HomeId = "CasaLilas",
		WalkSpeed = 11,
		Personality = { Sociability = 0.9, Curiosity = 0.7, Punctuality = 0.45, Energy = 0.55 },
		RoutineType = "Social",
		SuspicionTraits = { "VisitaVizinhos", "ParaDeRepente" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(198, 134, 66),
			ShirtColor = rgb(0, 184, 148),
			PantsColor = rgb(99, 110, 114),
			Description = {},
		},
	},
	{
		CharacterId = "Mel",
		DisplayName = "Mel",
		ModelName = "Mel",
		IsMain = false,
		HomeId = "CasaLilas",
		WalkSpeed = 12,
		Personality = { Sociability = 0.65, Curiosity = 0.9, Punctuality = 0.3, Energy = 0.8 },
		RoutineType = "Imprevisivel",
		SuspicionTraits = { "MudaDeIdeia", "ParaParaObservar" },
		AnimationConfig = {},
		Appearance = {
			SkinColor = rgb(255, 220, 177),
			ShirtColor = rgb(162, 155, 254),
			PantsColor = rgb(45, 52, 54),
			ArmColor = rgb(162, 155, 254),
			Description = {},
		},
	},
}

-- Falas usadas por quem não tem DialoguePool próprio
local DefaultDialogue = {
	Greeting = {
		"Oi, vizinho! Tudo bem?",
		"Bom dia! Ou boa tarde... perdi a noção da hora.",
		"Opa! Tava indo ali resolver umas coisas.",
		"Olá! Viu alguma coisa estranha por aí?",
	},
}

local byId: { [string]: Character } = {}
for _, character in list do
	byId[character.CharacterId] = character
end

return {
	List = list,
	ById = byId,
	DefaultDialogue = DefaultDialogue,
}
