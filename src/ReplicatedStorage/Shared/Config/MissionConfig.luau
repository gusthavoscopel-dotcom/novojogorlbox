--!strict
-- Modelos de missão. O servidor sorteia MissionsPerPlayer modelos diferentes por jogador e
-- preenche os alvos da partida. Conclusão e falha são sempre verificadas no servidor.
--
-- Description aceita: {targets} (lista de alvos), {target} (um alvo), {item}, {area},
-- {seconds}, {radius}. FailText é mostrado no painel de missões.
-- Regras gerais: missão não concluída quando a rodada termina = falha; se o morador-alvo sair
-- do jogo, a missão é cancelada (sem recompensa e sem impedir o fim antecipado da rodada).

export type MissionType = "Visit" | "Talk" | "Deliver" | "Find" | "Follow"

export type Template = {
	Id: string,
	Title: string,
	Description: string,
	Type: MissionType,
	AllowedRoles: { string }, -- Fase 1 só tem "Morador"; a Fase 2 adiciona Investigador e Imitador
	Reward: number,
	TimeLimit: number?, -- segundos após receber; nil = até o fim da rodada
	FailText: string,
	Weight: number,
	-- Parâmetros por tipo
	Count: number?, -- Visit/Talk: quantidade de alvos
	PoiKind: string?, -- Visit: "Public" ou "House"
	Radius: number?, -- Follow: distância máxima em studs
	Seconds: number?, -- Follow: segundos acumulados perto do alvo
	Items: { string }?, -- Find: objetos possíveis
}

local Templates: { Template } = {
	{
		Id = "Passeio",
		Title = "Passeio pelo bairro",
		Description = "Passe por: {targets}.",
		Type = "Visit",
		PoiKind = "Public",
		Count = 3,
		AllowedRoles = { "Morador" },
		Reward = 20,
		FailText = "Falha se a rodada acabar antes.",
		Weight = 3,
	},
	{
		Id = "Ronda",
		Title = "Ronda da vizinhança",
		Description = "Dê uma passada na frente de: {targets}.",
		Type = "Visit",
		PoiKind = "House",
		Count = 3,
		AllowedRoles = { "Morador" },
		Reward = 20,
		FailText = "Falha se a rodada acabar antes.",
		Weight = 2,
	},
	{
		Id = "Papo",
		Title = "Papo de vizinho",
		Description = "Converse com {targets}.",
		Type = "Talk",
		Count = 2,
		AllowedRoles = { "Morador" },
		Reward = 25,
		FailText = "Falha se a rodada acabar antes.",
		Weight = 3,
	},
	{
		Id = "Entrega",
		Title = "Entrega expressa",
		Description = "Retire uma encomenda no balcão do Mercado e deixe na caixa de correio: {target}.",
		Type = "Deliver",
		AllowedRoles = { "Morador" },
		Reward = 30,
		TimeLimit = 240,
		FailText = "Falha se passar de 4 minutos.",
		Weight = 2,
	},
	{
		Id = "Achados",
		Title = "Achados e perdidos",
		Description = "Alguém perdeu {item} {area}. Procure nos esconderijos (arbustos, lixeiras, caixotes).",
		Type = "Find",
		Items = { "um molho de chaves", "uma carteira", "um par de óculos", "um controle remoto" },
		AllowedRoles = { "Morador" },
		Reward = 30,
		FailText = "Falha se a rodada acabar antes.",
		Weight = 2,
	},
	{
		Id = "Sombra",
		Title = "Sombra discreta",
		Description = "Fique perto de {target} por {seconds} segundos (até {radius} studs de distância).",
		Type = "Follow",
		Radius = 18,
		Seconds = 25,
		AllowedRoles = { "Morador" },
		Reward = 30,
		TimeLimit = 300,
		FailText = "Falha se passar de 5 minutos.",
		Weight = 2,
	},
}

return {
	Templates = Templates,
}
