--!strict
-- Layout do bairro (gerado por MapService ao iniciar o servidor).
-- Grade 3x3 de quarteirões de 96 studs separados por ruas de 16 studs, com um anel de rua externo.
-- Para mover algo, altere a posição aqui; o MapService reconstrói tudo a partir destes dados.
--
--            NW: Lanchonete + Casa Laranja | N: Mercado        | NE: Casa do Yuri22 + Casa Verde
--            W:  Casa da Dona + Amarela     | Centro: Praça     | E:  Casa do Muriloso + Azul
--            SW: Parque                     | S: Ônibus + Tio Sam | SE: Casa Rosa + Casa Lilás
-- (Norte = -Z, Sul = +Z, Leste = +X, Oeste = -X)

export type Stand = {
	Offset: Vector3?, -- deslocamento do centro da área onde os moradores param
	Radius: number,
	MinRadius: number?, -- usado para não parar dentro de obstáculos centrais (ex.: chafariz)
}

export type Poi = {
	Id: string,
	DisplayName: string,
	Kind: string, -- "Public" | "House"
	Building: string, -- "Plaza" | "Market" | "Diner" | "Park" | "BusStop" | "House"
	Position: Vector3, -- centro da zona (para casas: a varanda)
	Facing: Vector3?, -- direção da fachada
	ZoneRadius: number, -- raio (horizontal) que conta como "estar no local"
	Stand: Stand,
	Size: Vector3?, -- prédios abertos (Market/Diner)
	Color: Color3?,
	RoofColor: Color3?,
}

export type Spot = {
	Id: string,
	DisplayName: string,
	Kind: string, -- "Bush" | "Trash" | "Crates"
	Position: Vector3,
	Area: string, -- dica de área usada pela missão "Achados e perdidos"
}

local GROUND_TOP = 1
local BLOCK_TOP = 1.5

local NORTH = Vector3.new(0, 0, -1)
local SOUTH = Vector3.new(0, 0, 1)
local EAST = Vector3.new(1, 0, 0)
local WEST = Vector3.new(-1, 0, 0)

local function at(x: number, z: number): Vector3
	return Vector3.new(x, BLOCK_TOP, z)
end

local function house(id: string, name: string, x: number, z: number, facing: Vector3, color: Color3): Poi
	return {
		Id = id,
		DisplayName = name,
		Kind = "House",
		Building = "House",
		Position = at(x, z),
		Facing = facing,
		ZoneRadius = 9,
		Stand = { Radius = 3 },
		Color = color,
		RoofColor = Color3.fromRGB(120, 62, 52),
	}
end

local Pois: { Poi } = {
	{
		Id = "Praca",
		DisplayName = "Praça Central",
		Kind = "Public",
		Building = "Plaza",
		Position = at(0, 0),
		ZoneRadius = 30,
		Stand = { Radius = 22, MinRadius = 11 },
	},
	{
		Id = "Mercado",
		DisplayName = "Mercado",
		Kind = "Public",
		Building = "Market",
		Position = at(0, -86),
		Facing = SOUTH,
		ZoneRadius = 22,
		Stand = { Radius = 6 },
		Size = Vector3.new(40, 12, 24),
		Color = Color3.fromRGB(46, 204, 113),
		RoofColor = Color3.fromRGB(39, 174, 96),
	},
	{
		Id = "Lanchonete",
		DisplayName = "Lanchonete",
		Kind = "Public",
		Building = "Diner",
		Position = at(-128, -86),
		Facing = SOUTH,
		ZoneRadius = 20,
		Stand = { Radius = 5 },
		Size = Vector3.new(32, 11, 22),
		Color = Color3.fromRGB(231, 76, 60),
		RoofColor = Color3.fromRGB(241, 196, 15),
	},
	{
		Id = "Parque",
		DisplayName = "Parque",
		Kind = "Public",
		Building = "Park",
		Position = at(-112, 112),
		ZoneRadius = 40,
		Stand = { Radius = 20 },
	},
	{
		Id = "PontoOnibus",
		DisplayName = "Ponto de Ônibus",
		Kind = "Public",
		Building = "BusStop",
		Position = at(-24, 73),
		Facing = NORTH,
		ZoneRadius = 12,
		Stand = { Radius = 2.5 },
		Color = Color3.fromRGB(52, 152, 219),
	},

	house("CasaYuri22", "Casa do Yuri22", 90, -74, SOUTH, Color3.fromRGB(231, 112, 104)),
	house("CasaVerde", "Casa Verde", 134, -74, SOUTH, Color3.fromRGB(129, 199, 132)),
	house("CasaLaranja", "Casa Laranja", -88, -74, SOUTH, Color3.fromRGB(255, 167, 38)),
	house("CasaDona", "Casa da Dona", -74, -20, EAST, Color3.fromRGB(186, 104, 200)),
	house("CasaAmarela", "Casa Amarela", -74, 20, EAST, Color3.fromRGB(255, 213, 79)),
	house("CasaMuriloso", "Casa do Muriloso", 74, -20, WEST, Color3.fromRGB(102, 187, 106)),
	house("CasaAzul", "Casa Azul", 74, 20, WEST, Color3.fromRGB(100, 181, 246)),
	house("CasaTioSam", "Casa do Tio Sam", 24, 74, NORTH, Color3.fromRGB(66, 133, 244)),
	house("CasaRosa", "Casa Rosa", 90, 74, NORTH, Color3.fromRGB(244, 143, 177)),
	house("CasaLilas", "Casa Lilás", 134, 74, NORTH, Color3.fromRGB(179, 157, 219)),
}

local Spots: { Spot } = {
	{ Id = "PracaArbusto", DisplayName = "Arbusto", Kind = "Bush", Position = at(-38, 22), Area = "na Praça" },
	{ Id = "PracaLixeira", DisplayName = "Lixeira", Kind = "Trash", Position = at(38, -22), Area = "na Praça" },
	{ Id = "ParqueArbusto1", DisplayName = "Arbusto", Kind = "Bush", Position = at(-148, 100), Area = "no Parque" },
	{ Id = "ParqueArbusto2", DisplayName = "Arbusto", Kind = "Bush", Position = at(-80, 150), Area = "no Parque" },
	{ Id = "ParqueLixeira", DisplayName = "Lixeira", Kind = "Trash", Position = at(-80, 76), Area = "no Parque" },
	{ Id = "MercadoCaixotes", DisplayName = "Caixotes", Kind = "Crates", Position = at(-34, -90), Area = "perto do Mercado" },
	{ Id = "MercadoLixeira", DisplayName = "Lixeira", Kind = "Trash", Position = at(-28, -74), Area = "perto do Mercado" },
	{ Id = "LanchoneteLixeira", DisplayName = "Lixeira", Kind = "Trash", Position = at(-104, -76), Area = "perto da Lanchonete" },
	{ Id = "LanchoneteCaixotes", DisplayName = "Caixotes", Kind = "Crates", Position = at(-150, -90), Area = "perto da Lanchonete" },
	{ Id = "OnibusLixeira", DisplayName = "Lixeira", Kind = "Trash", Position = at(-38, 74), Area = "no Ponto de Ônibus" },
	{ Id = "OnibusArbusto", DisplayName = "Arbusto", Kind = "Bush", Position = at(-8, 76), Area = "no Ponto de Ônibus" },
}

return {
	GroundTop = GROUND_TOP,
	BlockTop = BLOCK_TOP,
	BlockSize = 96,
	BlockPitch = 112, -- quarteirão + rua
	StreetWidth = 16,
	SidewalkWidth = 6,
	MapHalfSize = 184,

	-- Tipo de cada quarteirão da grade 3x3 (índices -1, 0, 1 em X e Z)
	Blocks = {
		{ X = 0, Z = 0, Type = "Plaza" },
		{ X = -1, Z = 1, Type = "Park" },
		{ X = 0, Z = -1, Type = "Lots" },
		{ X = 1, Z = -1, Type = "Lots" },
		{ X = -1, Z = -1, Type = "Lots" },
		{ X = -1, Z = 0, Type = "Lots" },
		{ X = 1, Z = 0, Type = "Lots" },
		{ X = 0, Z = 1, Type = "Lots" },
		{ X = 1, Z = 1, Type = "Lots" },
	},

	Pois = Pois,
	Spots = Spots,

	-- Balcão onde as encomendas da missão "Entrega expressa" são retiradas
	PackageCounter = at(28, -80),

	Lobby = {
		Center = Vector3.new(0, 80, -330), -- topo da plataforma
		Size = 64,
	},

	Colors = {
		Asphalt = Color3.fromRGB(72, 72, 78),
		StreetLine = Color3.fromRGB(255, 214, 10),
		Sidewalk = Color3.fromRGB(205, 205, 200),
		Lot = Color3.fromRGB(120, 190, 90),
		Plaza = Color3.fromRGB(232, 214, 180),
		Hedge = Color3.fromRGB(46, 125, 50),
		Trunk = Color3.fromRGB(121, 85, 72),
		Leaves = Color3.fromRGB(67, 160, 71),
		Water = Color3.fromRGB(79, 195, 247),
		Wood = Color3.fromRGB(161, 110, 70),
		Metal = Color3.fromRGB(96, 125, 139),
	},
}
