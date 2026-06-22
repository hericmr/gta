# santos-driver — Prompt completo para Claude Code (CLI) com GitHub Spec Kit

Jogo top-down de mundo aberto estilo **GTA 2**, ambientado em **Santos/SP**, feito em **Godot 4**.

> **Importante:** GTA 2 é top-down (visão de cima) com sprites 2.5D, **não** é 3D real. Este projeto segue esse estilo.

---

## Passo 0 — Setup do Spec Kit

Rode no terminal **antes** de abrir o Claude Code:

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init santos-driver --ai claude
cd santos-driver
claude
```

O Spec Kit usa os comandos: `/constitution`, `/specify`, `/plan`, `/tasks`, `/implement`.
Cole os blocos abaixo **um de cada vez**, na ordem.

---

## Passo 1 — `/constitution`

```
/constitution

Projeto: santos-driver — jogo top-down de mundo aberto estilo GTA 2, ambientado em Santos/SP.

Princípios não-negociáveis:
- Engine: Godot 4 (GDScript). Nada de Unity ou C#.
- Estilo: top-down 2D com sprites (NÃO é 3D real). Visão de cima, como GTA 1/2.
- Projeto novo e independente (sem dependência de assets externos por enquanto).
- Arquitetura modular por cenas: cada sistema (carro, player, câmera, mundo, missões) é uma cena/script isolado e testável separadamente.
- Protótipo "graybox" primeiro: geometria cinza e colliders antes de qualquer arte final. Arte vem depois.
- Mapa baseado no traçado real de Santos, mas estilizado — usar OpenStreetMap como referência de layout (orla, canais, centro), não precisão cartográfica.
- Tudo versionado no Git com commits pequenos e descritivos.
- Código comentado em português.
```

---

## Passo 2 — `/specify`

```
/specify

Marco 1 (protótipo jogável mínimo): um carro dirigível num mapa top-down de Santos.

Funcionalidades do marco 1:
1. Mapa top-down estilizado de Santos via TileMap, com pelo menos: orla, alguns quarteirões do centro, e ruas navegáveis. Prédios são colliders sólidos.
2. Carro controlável (CharacterBody2D ou RigidBody2D) com física arcade: aceleração, frenagem, ré, rotação proporcional à velocidade, atrito/drift leve. Controles WASD/setas.
3. Câmera top-down que segue o carro suavemente (lerp), com leve zoom-out conforme a velocidade.
4. Colisão funcional: o carro bate em prédios e não atravessa.
5. HUD mínimo: velocímetro simples.

Fora de escopo do marco 1 (não implementar ainda): NPCs, tráfego, pedestres, entrar/sair do carro a pé, missões, arte final, áudio.

Critérios de aceite: dá pra abrir o projeto no Godot 4, rodar, e dirigir o carro pela cidade colidindo com prédios, com câmera seguindo e velocímetro funcionando.
```

---

## Passo 3 — `/plan`

```
/plan

Stack: Godot 4.x, GDScript. Estrutura de pastas: /scenes, /scripts, /assets (placeholder), /maps.

Decisões técnicas a definir no plano:
- CharacterBody2D vs RigidBody2D pro carro (justifique a escolha pra física arcade simples).
- Como gerar o TileMap de Santos: comece com um mapa graybox feito à mão (tileset de placeholder), e documente um caminho futuro pra importar geometria do OpenStreetMap.
- Estrutura de cenas: Main.tscn como raiz, com World, Car, Camera e HUD como cenas instanciadas.
- Como o velocímetro lê a velocidade do carro (sinal/signal vs leitura direta).
```

---

## Passo 4 — `/tasks`

```
/tasks
```

---

## Passo 5 — `/implement`

```
/implement
```

---

## Notas práticas

- O `/implement` vai gerar arquivos `.gd` e `.tscn`, mas cenas do Godot (`.tscn`) são chatas de montar 100% via texto. Provavelmente será necessário abrir o editor do Godot e ajustar nós manualmente — peça ao Claude para sinalizar e pedir confirmação nesses pontos.
- Verifique a versão do Spec Kit antes de começar: os comandos podem ter mudado. Consulte https://github.com/github/spec-kit
- Fluxo recomendado de desenvolvimento: protótipo graybox jogável primeiro → arte e cidade real depois.

## Roadmap futuro (pós-marco 1)

- Entrar/sair do carro a pé (troca de nó controlado).
- NPCs e tráfego via navigation polygons + waypoints.
- Sistema de missões (máquina de estados).
- Importação de geometria de ruas do OpenStreetMap → colliders/navmesh.
- Integração de arte e ambientação.
