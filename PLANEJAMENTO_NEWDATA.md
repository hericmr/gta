# Planejamento: Integração de dados reais de Santos ao jogo

## Dados disponíveis em `newdata/`

| Arquivo | Origem | Conteúdo |
|---|---|---|
| `bairros.json` | cartografiasocial | 59 polígonos de bairros com nome |
| `lugares_famosos.json` | Geosantos | 147 pontos de interesse com nome, descrição, categoria, endereço |
| `linhas_onibus.json` | wheresheric | 41 linhas com percurso ida/volta e paradas |
| `converter.py` | — | Script Python que gera os 3 arquivos acima a partir das fontes |

Todos os arquivos já estão em coordenadas de jogo (pixels pré-escala, mesma fórmula de `satelite_stream.gd::_geo_para_game`).

---

## Fase 1 — Camada de Bairros

**Arquivo:** `scripts/camada_bairros.gd` (novo Node2D, filho de `$World`)

**O que faz:**
- Carrega `newdata/bairros.json` no `_ready()`
- Desenha o contorno de cada bairro com `Line2D` (z_index = -4, abaixo das ruas)
  - Cor: branco com alpha 0.15 — visível mas não agressiva
  - Largura: 0.08 unidades pré-escala (~1.2 m real)
- Detecta qual bairro contém o player (ponto-em-polígono, roda a cada 1 s no `_process`)
- Expõe sinal `bairro_mudou(nome: String)` → HUD exibe o nome no canto superior esquerdo

**Considerações:**
- Algoritmo point-in-polygon em GDScript é simples (ray casting)
- Alguns bairros têm polígonos que extrapolam levemente o bbox do mapa (ex.: Morro Saboó) — isso é normal, o Line2D simplesmente sai da tela

**Integração:**
- `Main.tscn`: adicionar `CamadaBairros` como filho de `$World`
- `hud.gd`: adicionar `Label` `NomeBairro` no canto superior esquerdo
- `main.gd`: conectar o sinal `bairro_mudou` ao HUD

---

## Fase 2 — Camada de Lugares de Interesse

**Arquivo:** `scripts/camada_pontos.gd` (novo Node2D, filho de `$World`)

**O que faz:**
- Carrega `newdata/lugares_famosos.json`
- Por categoria, define uma cor distinta:
  - Assistência Social → laranja
  - Saúde → verde
  - Educação → azul
  - Cultura / Patrimônio Histórico → roxo
  - Turismo / Lazer → ciano
  - Comunidades → amarelo
  - Religião → rosa
  - Infraestrutura → cinza
- Desenha cada ponto como um `Polygon2D` circular pequeno (raio ~8 px pré-escala) com z_index = 0
- Quando o player entra em raio de ~300 px (pré-escala ≈ 20 m real): exibe painel de info no HUD
  - Campos: nome, categoria, endereço, primeiros 200 chars da descrição
  - Tecla `E` para abrir descrição completa

**Integração:**
- `Main.tscn`: adicionar `CamadaPontos` como filho de `$World`
- `hud.gd`: adicionar `Panel` `InfoPonto` (inicialmente oculto)
- `main.gd`: a cada frame, passar `ref.position` para `CamadaPontos.atualizar(pos)`

**Filtro no mapa (Fase 2b):**
- No mini-mapa (`mapa.gd`), desenhar marcadores de pontos com a mesma paleta de cores
- Tecla `F` abre/fecha legenda de categorias com toggle de visibilidade por categoria

---

## Fase 3 — Camada de Linhas de Ônibus

**Arquivo:** `scripts/camada_onibus.gd` (novo Node2D, filho de `$World`)

**O que faz:**
- Carrega `newdata/linhas_onibus.json`
- Desenha o percurso ida de cada linha com `Line2D`:
  - Cor única por linha (hash do `linha_id` → matiz HSV)
  - Largura 0.25 pré-escala (~3.75 m)
  - z_index = -5 (abaixo dos bairros)
- Desenha paradas como pequenos quadrados brancos (4×4 px pré-escala)
- Começa **invisível** — toggled com tecla `O`
- Quando visível e player se aproxima de uma parada (~150 px):
  - HUD exibe nome da parada e nome da linha

**Sem NPC de ônibus nesta fase** — percurso é apenas visual/informativo.

**Integração:**
- `Main.tscn`: adicionar `CamadaOnibus` como filho de `$World`
- `main.gd`: `Input.is_action_just_pressed("onibus_toggle")` → `$World/CamadaOnibus.toggle()`
- `project.godot`: adicionar action `onibus_toggle` → tecla `O`

---

## Ordem de implementação recomendada

```
[x] Converter dados (converter.py já feito)
[ ] Fase 1a — Desenhar contornos de bairros
[ ] Fase 1b — Detectar bairro atual + Label no HUD
[ ] Fase 2a — Pontos de interesse no mapa
[ ] Fase 2b — Painel de info ao se aproximar
[ ] Fase 3a — Linhas de ônibus visíveis (toggle O)
[ ] Fase 3b — Paradas com nome no HUD
[ ] Fase 2c — Mini-mapa com filtro de categoria
```

---

## Notas técnicas

**Coordenadas:** todos os dados em `newdata/*.json` usam o mesmo sistema do jogo:
- `x, y` = pixels pré-escala (dividir por 15 para metros reais)
- Para posição Godot real: `Vector2(x, y) * ESCALA` — mas o `$World` já aplica `scale = Vector2(15, 15)`, então basta usar `Vector2(x, y)` diretamente nos filhos de `$World`

**Atualizar dados:** rodar `python3 newdata/converter.py` sempre que as fontes forem alteradas.

**Bairros fora do bbox:** polígonos podem ter vértices com x negativo ou y > 11520 — normal, são bairros que tocam a borda do mapa. Não causa crash; os Line2D simplesmente saem da viewport.
