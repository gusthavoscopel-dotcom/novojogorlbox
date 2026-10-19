# Testes

## 1. Verificações automáticas (fora do Studio)

Pré-requisito: ferramentas do `rokit.toml` (Rojo 7.6.1, Lune 0.10.4, luau-lsp 1.60.0).

```bash
# 1) place e sourcemap
rojo build default.project.json -o build/MeuVizinhoEUmNPC.rbxlx
rojo sourcemap default.project.json -o sourcemap.json

# 2) type-check estrito contra a API atual do Roblox
curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
luau-lsp analyze --platform roblox --definitions=@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src

# 3) lógica pura e coerência das configurações (21 testes)
lune run tests/run.luau

# 4) gera o mapa fora do Studio e confere a geometria
lune run tests/map.luau mapa.json
python3 tests/render_map.py mapa.json docs/mapa.png   # opcional: imagem vista de cima (precisa de Pillow)
```

Resultado esperado: nenhum erro no `luau-lsp`, `21 testes passaram, 0 falharam` e `Geometria OK`.

## 2. O que só o Studio confirma

Estes pontos dependem do motor do Roblox e não puderam ser executados aqui. Confira primeiro:

| Ponto | Como confirmar |
|---|---|
| NPCs são criados com `Players:CreateHumanoidModelFromDescriptionAsync` | `Workspace.Residents` recebe os NPCs no começo da partida. |
| Animações R15 padrão (`AssetConfig`) carregam nos NPCs | NPCs andam com animação. Para conferir os IDs: durante uma partida, abra `Workspace > SeuPersonagem > Animate > walk > WalkAnim` e compare o `AnimationId` com `AssetConfig.Animations.Walk` (o mesmo para `run > RunAnim`). Se for diferente, copie o do Animate, para NPC e jogador andarem igual. |
| Disfarce com `LoadCharacterWithHumanoidDescriptionAsync` | Na partida, seu personagem tem as cores/nome do morador e nasce na varanda da casa dele. |
| Telhado das casas (WedgePart) | O telhado deve formar um "Λ". Se aparecer um "V", troque `if side == 1` por `if side == -1` em `MapService.buildHouse`. |
| Pathfinding no mapa gerado | NPCs chegam aos destinos andando pelas calçadas, sem ficar presos em quinas. |
| Layout da interface | Nada sobreposto ao topo do Roblox; painéis legíveis no PC e no emulador de celular. |

## 3. Como testar com vários jogadores no Studio

1. Aba **Test** > em **Clients and Servers**, escolha **Local Server** e o número de jogadores (2 a 4 é o bastante para a maioria dos testes).
2. Clique **Start**. Abre uma janela do servidor e uma por jogador.
3. Use a janela do **servidor** para olhar `Workspace.Residents`, o Output do servidor e apagar coisas de propósito.
4. Para celular: em uma janela de jogador, aba **Test** > **Device** e escolha um telefone pequeno em modo paisagem.
5. Para testar sozinho, deixe `GameConfig.MinPlayers = 1` e use **Play** normal.

Dica: para testes rápidos, use `IntermissionTime = 5`, `RoundDuration = 60` e `ResultsTime = 8` no `GameConfig`, e defina `FixedSeed` para repetir a mesma partida.

## 4. Checklist obrigatório

| # | Cenário | Passos | Resultado esperado | Fase |
|---|---|---|---|---|
| 1 | Servidor com poucos jogadores | Play com 1 jogador (`MinPlayers = 1`) | Contagem de 15 s, partida começa, 9 NPCs + você = 10 moradores; os 4 principais sempre presentes | 1 |
| 2 | Servidor cheio dentro do limite | Local Server com 10 jogadores (ou reduza `MaxParticipants` e teste com 4) | Cada jogador vira um morador diferente; sobram pelo menos `MinNPCs` NPCs; jogadores além do limite esperam no lobby | 1 |
| 3 | NPC preso em um caminho | Na janela do servidor, coloque uma Part ancorada grande na frente de um NPC andando | NPC recalcula o caminho; se não houver saída e nenhum jogador estiver perto, reaparece no destino; o jogo continua | 1 |
| 4 | Jogador sai durante a rodada (equivalente da Fase 1 para "sair durante a votação") | Com 2 jogadores, feche a janela de um deles no meio da partida | O morador dele some; missões que tinham ele como alvo viram "cancelada" com aviso; a revelação final mostra "(saiu)"; se ele era o único participante, a rodada termina com "Todos os jogadores da partida saíram." | 1 (votação na 2) |
| 5 | Concluir a mesma missão duas vezes | Conclua "Achados e perdidos" e procure de novo no mesmo esconderijo; ou entregue e tente entregar de novo | Nenhum progresso extra; aviso "Nada de interessante aqui." / "Você não tem encomenda para esta casa."; fichas da missão contadas uma vez só | 1 |
| 6 | Cliente tentando dar moedas a si mesmo | Na janela do jogador, Command Bar (contexto cliente): `game.Players.LocalPlayer.leaderstats.Fichas.Value = 999` | Só aquele cliente vê 999; na janela do servidor o valor não muda; não existe remote que conceda fichas | 1 |
| 7 | Rodada terminando por tempo | `RoundDuration = 60`, não conclua as missões | Tela "FIM DE RODADA", motivo "O tempo acabou!", missões abertas marcadas como falha, +10 de participação | 1 |
| 8 | Empate na votação | — | — | 2 |
| 9 | NPC removido inesperadamente | Na janela do servidor, apague um NPC de `Workspace.Residents` | Aviso no Output "removido inesperadamente"; o NPC reaparece na casa dele em 5 s e retoma a rotina | 1 |
| 10 | Falha no salvamento | — | — | 4 |
| 11 | Reinício da rodada | Deixe duas rodadas seguidas acontecerem | Entre rodadas `Workspace.Residents` fica vazio; missões e disfarces são limpos; todos voltam ao próprio avatar no lobby; a nova rodada tem outra seed | 1 |
| 12 | Interface em tela pequena | Emulador de celular pequeno, paisagem | Painel de missões começa recolhido; barra do topo, avisos e resultado cabem na tela sem cobri-la inteira | 1 |

Cenários extras da Fase 1:

| Cenário | Resultado esperado |
|---|---|
| Entrar no meio da partida | Fica no lobby com "Partida em andamento. Você entra na próxima!" e recebe a revelação no fim |
| Morrer na partida (na janela do servidor: `Humanoid.Health = 0` no seu personagem) | Renasce disfarçado na sua casa após 3 s, com as mesmas missões |
| Conversar com um NPC | NPC para, vira para você e responde com uma fala do personagem; conta para "Papo de vizinho" |
| Conversar com um jogador disfarçado | Você recebe a fala automática do personagem; o outro jogador recebe "X puxou conversa com você." |
| Prompt de longe | Prompts só aparecem a 8 studs; o servidor recusa acima de 12 studs |
| Botão de reset | "Reset Character" desativado no menu Esc |
