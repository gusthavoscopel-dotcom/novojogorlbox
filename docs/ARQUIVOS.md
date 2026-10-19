# Fase 1 — arquivo por arquivo

Cada linha diz onde o objeto fica no Roblox Studio, o tipo do objeto e do que ele depende.
O código completo está no arquivo indicado (caminho relativo à raiz do repositório).

## Instalação manual (copiar e colar)

1. Em **ReplicatedStorage**, crie a pasta `Shared`; dentro dela, a pasta `Config`.
2. Em **ServerScriptService**, crie as pastas `Logic` e `Services`.
3. Em **StarterPlayer > StarterPlayerScripts**, crie as pastas `Controllers` e `UI`.
4. Crie cada objeto da tabela abaixo com o **nome exato** e o **tipo exato**, e cole o conteúdo do arquivo.
5. Se o place veio do template Baseplate, apague o `SpawnLocation` dele.
6. Game Settings > Avatar > Avatar Type = **R15** (lugares publicados).

Não crie os remotes nem as pastas `Remotes`, `GameState`, `NPCModels`, `Lobby`, `ActiveMap` e
`Residents`: o servidor cria tudo isso ao iniciar.

## Compartilhado — ReplicatedStorage

| Objeto | Local no Studio | Tipo | Arquivo | Depende de | Como verificar |
|---|---|---|---|---|---|
| GameConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/GameConfig.luau` | — | Mude `IntermissionTime` para 5 e veja a contagem do lobby começar em 5 s. |
| CharacterConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/CharacterConfig.luau` | — | Na partida, os nomes sobre os moradores (Yuri22, Dona, Muriloso, Tio Sam...) e as cores de roupa batem com a configuração. |
| RoutineConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/RoutineConfig.luau` | — | Um NPC "Trabalhador" (Tio Sam, Lúcia, Jorginho) passa a maior parte do tempo no local de trabalho. |
| MissionConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/MissionConfig.luau` | — | O painel de missões mostra títulos e descrições destes modelos. |
| MapConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/MapConfig.luau` | — | O bairro gerado tem as casas e lugares nas posições da imagem `docs/mapa.png`. |
| AssetConfig | ReplicatedStorage > Shared > Config | ModuleScript | `src/ReplicatedStorage/Shared/Config/AssetConfig.luau` | — | NPCs andam com animação de caminhada; sem aviso "animação ... não carregou" no Output. |
| Remotes | ReplicatedStorage > Shared | ModuleScript | `src/ReplicatedStorage/Shared/Remotes.luau` | — | Durante o Play, aparecem `ReplicatedStorage.Remotes` (5 remotes) e `ReplicatedStorage.GameState` com atributos `Phase` e `PhaseEndsAt`. |
| Types | ReplicatedStorage > Shared | ModuleScript | `src/ReplicatedStorage/Shared/Types.luau` | — | Só tipos; nada a verificar em jogo. |

## Servidor — ServerScriptService

| Objeto | Local no Studio | Tipo | Arquivo | Depende de | Como verificar |
|---|---|---|---|---|---|
| Bootstrap | ServerScriptService | Script | `src/ServerScriptService/Bootstrap.server.luau` | todos os Services | Output mostra `[Bootstrap] ... iniciado` para os 5 serviços. |
| MatchSetup | ServerScriptService > Logic | ModuleScript | `src/ServerScriptService/Logic/MatchSetup.luau` | CharacterConfig, Types | Os 4 principais aparecem em toda partida; cada jogador vira um morador diferente. |
| RoutinePlanner | ServerScriptService > Logic | ModuleScript | `src/ServerScriptService/Logic/RoutinePlanner.luau` | RoutineConfig, Types | NPCs não ficam parados para sempre e nem repetem o mesmo lugar duas vezes seguidas; no fim da rodada voltam para casa. |
| MissionLogic | ServerScriptService > Logic | ModuleScript | `src/ServerScriptService/Logic/MissionLogic.luau` | MissionConfig, Types | Missões nunca pedem para conversar consigo mesmo ou entregar na própria casa. |
| EconomyService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/EconomyService.luau` | GameConfig | Lista de jogadores (Tab) mostra a coluna **Fichas**; ela só aumenta na tela de resultado. |
| MapService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/MapService.luau` | MapConfig | Ao dar Play surgem `Workspace.Lobby` e `Workspace.ActiveMap` com placas sobre cada lugar. |
| CharacterService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/CharacterService.luau` | CharacterConfig, GameConfig | Na partida, seu personagem tem as cores e o nome do morador sorteado; ao fim, volta ao seu avatar no lobby. |
| NPCService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/NPCService.luau` | AssetConfig, CharacterConfig, GameConfig, MapConfig, RoutineConfig, RoutinePlanner, CharacterService, MapService | `Workspace.Residents` recebe os NPCs, que andam pelas calçadas entre os lugares; ao conversar, o NPC para e vira para você. |
| MissionService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/MissionService.luau` | CharacterConfig, MapConfig, MissionConfig, GameConfig, Remotes, Types, MissionLogic | Painel mostra 3 missões; progresso atualiza ao cumprir cada etapa; aviso "Missão concluída". |
| InteractionService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/InteractionService.luau` | CharacterConfig, GameConfig, Remotes, MissionService, NPCService, RoundService | Prompts "Conversar", "Procurar", "Retirar encomenda" e "Entregar encomenda" respondem só durante a partida e só de perto. |
| RoundService | ServerScriptService > Services | ModuleScript | `src/ServerScriptService/Services/RoundService.luau` | CharacterConfig, GameConfig, Remotes, Types, MatchSetup, CharacterService, EconomyService, MapService, MissionService, NPCService | Ciclo Lobby → contagem → partida → resultado → lobby se repete; Output mostra `rodada N | seed X`. |

## Cliente — StarterPlayer > StarterPlayerScripts

| Objeto | Local no Studio | Tipo | Arquivo | Depende de | Como verificar |
|---|---|---|---|---|---|
| ClientBootstrap | StarterPlayerScripts | LocalScript | `src/StarterPlayer/StarterPlayerScripts/ClientBootstrap.client.luau` | Remotes, Controllers | Sem erros `[Cliente]` no Output do cliente. |
| UIKit | StarterPlayerScripts > UI | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/UI/UIKit.luau` | — | Painéis diminuem proporcionalmente no emulador de celular (Test > Device). |
| UIController | StarterPlayerScripts > Controllers | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/UIController.luau` | GameConfig, Remotes, Types, UIKit | Barra no topo com fase e relógio, avisos à direita, falas embaixo e tela "Quem era quem?" no fim. |
| MissionController | StarterPlayerScripts > Controllers | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/MissionController.luau` | Remotes, Types, UIKit | Painel "Missões secretas" à esquerda, recolhível pelo cabeçalho. |
| InteractionController | StarterPlayerScripts > Controllers | ModuleScript | `src/StarterPlayer/StarterPlayerScripts/Controllers/InteractionController.luau` | — | Você não vê o "Conversar" do seu próprio personagem; o menu Esc não tem "Reset Character" habilitado. |

## Ferramentas e testes (fora do Studio)

| Arquivo | Para quê |
|---|---|
| `default.project.json` | Mapa de pastas do Rojo para o Studio. |
| `rokit.toml` | Versões fixas de Rojo, Lune e luau-lsp. |
| `build/MeuVizinhoEUmNPC.rbxlx` | Place pronto, gerado com `rojo build`. |
| `tests/run.luau` | Testes da lógica pura e da coerência das configurações (Lune). |
| `tests/map.luau` | Gera o mapa fora do Studio e confere a geometria (Lune). |
| `tests/render_map.py` | Desenha `docs/mapa.png` a partir do mapa gerado. |
