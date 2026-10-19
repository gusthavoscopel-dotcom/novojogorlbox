--!strict
-- Ponto de entrada do servidor: inicia os serviços em ordem, cada um protegido por pcall.
-- Ordem importa: o mapa precisa existir antes de criar personagens, e o RoundService por último.

local Services = script.Parent.Services

local steps: { { Name: string, Essential: boolean, Start: () -> () } } = {
	{ Name = "EconomyService", Essential = false, Start = function()
		require(Services.EconomyService).Start()
	end },
	{ Name = "MapService", Essential = true, Start = function()
		require(Services.MapService).Start()
	end },
	{ Name = "CharacterService", Essential = true, Start = function()
		require(Services.CharacterService).Start()
	end },
	{ Name = "InteractionService", Essential = true, Start = function()
		require(Services.InteractionService).Start()
	end },
	{ Name = "RoundService", Essential = true, Start = function()
		require(Services.RoundService).Start()
	end },
}

for _, step in steps do
	local ok, err = pcall(step.Start :: any)
	if ok then
		print(`[Bootstrap] {step.Name} iniciado`)
	else
		warn(`[Bootstrap] falha ao iniciar {step.Name}: {err}`)
		if step.Essential then
			warn("[Bootstrap] serviço essencial falhou; o jogo não vai funcionar até o erro acima ser corrigido.")
			break
		end
	end
end
