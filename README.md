# GTA Santos

Jogo top-down estilo GTA 2 ambientado na cidade real de **Santos/SP**, feito em Godot 3. O mapa é gerado a partir de dados reais do OpenStreetMap e imagens de satélite. Ruas, quadras e colisões de prédios refletem a cidade como ela é.

Jogável no browser: **[hericmr.github.io/gta](https://hericmr.github.io/gta)**

---

## O que tem no jogo

- Mapa real de Santos gerado a partir do OpenStreetMap
- Imagens de satélite carregadas por streaming conforme o jogador se move
- Carro com física arcade: aceleração, frenagem, ré e derrapagem lateral
- Marcas de pneu no asfalto durante derrapagens
- Rádio dentro do carro com faixas de áudio
- Colisões com prédios baseadas em dados reais do OSM
- Transição a pé ↔ carro (tecla Enter)
- Velocímetro no HUD
- Zoom dinâmico da câmera conforme velocidade do carro
- Exportado como HTML5 — roda direto no browser, sem instalação

---

## Controles

| Tecla | Ação |
|---|---|
| `W` / `↑` | Acelerar / Andar para frente |
| `S` / `↓` | Frear / Ré / Andar para trás |
| `A` / `←` | Virar à esquerda |
| `D` / `→` | Virar à direita |
| `Enter` | Entrar / Sair do carro (quando próximo) |

---

## Tecnologias

| Componente | Tecnologia |
|---|---|
| Engine | Godot 3.6 (GDScript) |
| Exportação | HTML5 (WebAssembly) |
| Mapa base | OpenStreetMap via Overpass API |
| Imagens de satélite | ESRI World Imagery (zoom 18, tiles 256px) |
| Pipeline de dados | Python 3 (sem framework — só stdlib + Pillow) |
| Hospedagem | GitHub Pages |

---

## Arquitetura do projeto

```
gta_santos/
├── scenes/
│   ├── Main.tscn          ← cena raiz: junta World, Car, Player e HUD
│   ├── WorldOSM.tscn      ← nó do mapa (ruas, prédios, satélite)
│   ├── Car.tscn           ← carro dirigível
│   ├── Player.tscn        ← personagem a pé
│   └── HUD.tscn           ← velocímetro
│
├── scripts/
│   ├── main.gd            ← spawn, transição a pé/carro, câmeras
│   ├── car.gd             ← física arcade do carro + rádio + marcas de pneu
│   ├── player.gd          ← movimentação e animação do personagem
│   ├── world_osm.gd       ← carrega santos.json e meta.json; monta ruas/prédios
│   ├── satelite_stream.gd ← streaming de tiles de satélite por posição
│   └── hud.gd             ← atualiza label do velocímetro
│
├── assets/
│   ├── carros/SP_021.png  ← sprite do carro
│   ├── human/
│   │   └── player_walk.png  ← spritesheet do personagem (5 frames)
│   ├── radio/             ← faixas de áudio do rádio do carro (.mp3)
│   └── tiles/
│       ├── meta.json      ← bbox, zoom e dimensões do mapa de tiles
│       └── z18_*.png      ← tiles de satélite (zoom 18, ESRI World Imagery)
│
├── maps/
│   ├── santos.json        ← ruas e prédios de Santos (gerado por importar_santos.py)
│   └── santos_osm_raw.json  ← dados brutos OSM (intermediário, não carregado pelo jogo)
│
├── importar_santos.py     ← baixa dados OSM e gera maps/santos.json
├── baixar_tiles.py        ← baixa tiles de satélite para assets/tiles/
├── generate_grid.py       ← gera tiles de referência para arte (chão + prédios)
├── baixar_referencia.py   ← utilitário auxiliar de referência
├── patch_html.py          ← pós-processa o HTML exportado pelo Godot
├── planning.md            ← plano de implementação do modo multiplayer
└── requirements.txt       ← dependências Python
```

---

## Como o mapa funciona

### Coordenadas

O jogo usa um sistema de coordenadas planas derivado do bounding box de Santos:

```
bbox: lat [-23.995, -23.905]  lon [-46.38, -46.285]
mapa: 8000 × 8292 px (pré-escala)
ESCALA = 15.0  →  1 pixel pré-escala ≈ 1 metro

Conversão lat/lon → posição Godot:
  x = (lon - lon_min) / (lon_max - lon_min) * 8000  * 15
  y = (1 - (lat - lat_min) / (lat_max - lat_min)) * 8292 * 15
```

Essa mesma lógica está implementada em `scripts/satelite_stream.gd` nas funções `_geo_para_game`, `_pos_para_lat` e `_pos_para_lon`.

### Tiles de satélite

O `satelite_stream.gd` mantém uma janela de **9×9 tiles** ao redor do jogador (raio 4). Conforme o jogador se move, tiles distantes são descarregados e novos são carregados do `.pck` (no HTML5) ou do disco (no desktop). Cada tile é um PNG de 256×256px do zoom 18 do ESRI World Imagery.

### Ruas e prédios

O `world_osm.gd` carrega `maps/santos.json`, que contém:
- **`ruas`**: polylines com largura para desenho visual (sem colisão)
- **`prédios`**: polígonos que viram `CollisionPolygon2D` + `Polygon2D` visual

No HTML5 esses arquivos são buscados diretamente do GitHub Pages via `HTTPRequest`. No desktop são lidos do disco. Os prédios são instanciados em lotes de 60 por frame para não travar na inicialização.

---

## Rodando localmente (desktop)

### Pré-requisitos

- [Godot 3.6](https://godotengine.org/download/archive/3.6-stable/) (versão 3, não 4)
- Python 3.11+ com pip

### 1. Instalar dependências Python

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Baixar dados do mapa

```bash
# Gera maps/santos.json (ruas e prédios via OpenStreetMap)
python3 importar_santos.py

# Baixa tiles de satélite para assets/tiles/
python3 baixar_tiles.py
```

`importar_santos.py` usa a Overpass API (gratuita, sem chave) e leva alguns minutos dependendo da conexão. `baixar_tiles.py` baixa ~81 tiles PNG do ESRI World Imagery.

### 3. Abrir no Godot

```
Godot → Import → selecionar project.godot
F5 para rodar
```

O jogo inicia com o carro e o player no centro de Santos.

---

## Scripts Python

### `importar_santos.py`

Consulta a Overpass API do OSM e gera `maps/santos.json`.

```bash
python3 importar_santos.py
```

**O que faz:**
1. Baixa todas as ruas (`highway=*`) dentro do bbox de Santos
2. Baixa todos os prédios (`building=*`)
3. Converte lat/lon para coordenadas de pixel (pré-escala)
4. Calcula largura de cada rua por tipo (motorway → 12px, residential → 4px, etc.)
5. Salva `maps/santos.json` com arrays de `ruas` e `predios`

Não precisa de biblioteca externa — usa só `urllib` e `json` da stdlib.

### `baixar_tiles.py`

Baixa tiles de satélite (ESRI World Imagery, zoom 18) e salva em `assets/tiles/`.

```bash
python3 baixar_tiles.py
```

**O que faz:**
1. Calcula o range de tiles XY que cobre o bbox de Santos no zoom 18
2. Baixa cada tile como PNG com delay de 0.3s entre requests (respeita rate limit)
3. Salva como `z18_<tx>_<ty>.png`
4. Gera `assets/tiles/meta.json` com bbox, dimensões e range de tiles

Dependência: `Pillow` (só para verificar integridade dos PNGs).

### `generate_grid.py`

Gera tiles de **referência visual** para uso como base de arte do jogo. Não é usado em runtime pelo Godot — é uma ferramenta de desenvolvimento para quando você quiser desenhar tiles estilizados GTA por cima da planta real.

```bash
# Tile central de Santos
python3 generate_grid.py

# Área por bounding box
python3 generate_grid.py --bbox -23.98 -46.35 -23.94 -46.30

# Tile maior
python3 generate_grid.py --tile-meters 512 --tile-px 512 --tiles 0,0
```

**Saídas em `output/`:**
- `ground_ref_X_Y.png` — planta do chão com ruas, água e parques
- `buildings_X_Y.json` — footprints e alturas dos prédios (para efeito 2.5D futuro)
- `buildings_ref_X_Y.png` — footprints numerados (número = índice no JSON)

### `patch_html.py`

Aplica patches no HTML exportado pelo Godot para habilitar SharedArrayBuffer (necessário para WebAssembly com threads) via cabeçalhos COOP/COEP usando um Service Worker.

```bash
python3 patch_html.py
```

Executar depois de cada exportação HTML5 pelo Godot.

---

## Exportando para HTML5

```bash
# 1. No Godot: Project → Export → HTML5 → Export Project
#    Salvar como santos-gta.html na raiz do projeto

# 2. Aplicar patch (SharedArrayBuffer / Service Worker)
python3 patch_html.py

# 3. Fazer push para GitHub Pages
git add santos-gta.* coi-serviceworker.js
git commit -m "update build"
git push
```

O arquivo `coi-serviceworker.js` é o Service Worker que injeta os cabeçalhos COOP/COEP necessários para o WebAssembly rodar no browser.

---

## Física do carro

| Parâmetro | Valor | Descrição |
|---|---|---|
| `velocidade_maxima` | 580 | Velocidade máxima (unidades/s) |
| `aceleracao` | 400 | Taxa de aceleração |
| `atrito` | 300 | Desaceleração natural |
| `frenagem` | 900 | Desaceleração ao frear |
| `velocidade_re` | 0.4 | Fator da velocidade de ré (40% da max) |
| Rotação | 195°/s | Velocidade de virada em velocidade máxima |
| Derrapagem lateral | até 280 u/s | Velocidade lateral máxima em curvas |

O HUD mostra a velocidade convertida para km/h aproximado (`vel * 0.18`).

---

## Próximos passos — Multiplayer

O plano de implementação de multiplayer com Supabase está detalhado em [`planning.md`](./planning.md). Em resumo:

- Jogador informa sua rua ou usa GPS do browser para entrar no jogo na localização real
- Posições são sincronizadas via Supabase (PostgreSQL + REST API gratuita)
- Outros jogadores aparecem como sprites no mapa em tempo real
- Geocodificação via Nominatim (OSM, gratuito, sem chave de API)

---

## Dados e licenças

- **OpenStreetMap** — dados de ruas e prédios licenciados sob [ODbL](https://opendatacommons.org/licenses/odbl/)
- **ESRI World Imagery** — tiles de satélite para uso não-comercial
- **Godot Engine** — [MIT License](https://godotengine.org/license)
