--!strict
-- IDs de assets externos. Se algum ID falhar ao carregar, o jogo continua funcionando:
-- o NPC apenas anda sem animação.
--
-- Estas são as animações R15 padrão da própria Roblox (as mesmas do script "Animate" que todo
-- jogador recebe). Mantê-las iguais para NPCs e jogadores evita que a animação denuncie quem é NPC.
-- Áudios entram na Fase 3.

return {
	Animations = {
		Idle = "rbxassetid://507766388",
		Walk = "rbxassetid://507777826",
		Run = "rbxassetid://507767714",
	},
}
