# GTA Santos — Pipeline de Tiles de Referência

Gera tiles de referência a partir de dados reais de Santos/SP (OpenStreetMap),
preparados para o fluxo de trabalho de um jogo top-down estilo GTA 2 no Godot 3,
com arquitetura separada de **chão** e **prédios** para efeito 2.5D futuro.

---

## Instalação

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Python 3.11+.

---

## Uso

### Tile central de Santos (default)

```bash
python generate_grid.py
```

Gera o tile `(0,0)` na pasta `output/`.

### Tiles específicos

```bash
python generate_grid.py --tiles 0,0 1,0 0,1 -1,0
```

### Área por bounding box

```bash
python generate_grid.py --bbox -23.98 -46.35 -23.94 -46.30
```

### Tile maior / mais detalhado

```bash
# 512m por tile, 512px de saída
python generate_grid.py --tile-meters 512 --tile-px 512 --tiles 0,0

# tile menor, mais granular (128m)
python generate_grid.py --tile-meters 128 --tile-px 256 --tiles 0,0 1,0
```

> **Atenção**: `tile-meters` e `tile-px` ficam gravados em `grid.json` na primeira execução.
> Todas as execuções seguintes devem usar os mesmos valores ou o script recusa.

### Altura padrão de prédios

```bash
# Usa 5 andares (15m) como fallback quando OSM não informa
python generate_grid.py --default-building-height 5
```

---

## Saídas por tile

```
output/
  grid.json                    ← manifesto da grade (não apague)
  ground_ref_0_0.png           ← referência do chão para desenhar por cima
  buildings_0_0.json           ← footprints + altura dos prédios
  buildings_ref_0_0.png        ← footprints numerados (número = índice no JSON)
  cache/                       ← dados OSM cacheados (delete para re-baixar)
```

---

## Como a grade garante alinhamento

A origem (`ox`, `oy`) é calculada **uma vez** e gravada em `grid.json`:

```
(x_raw, y_raw) = UTM(ref_lat=-23.9608, ref_lon=-46.3322)
ox = floor(x_raw / tile_meters) * tile_meters
oy = floor(y_raw / tile_meters) * tile_meters
```

O tile `(tx, ty)` sempre cobre exatamente:
```
xmin = ox + tx * tile_meters
ymin = oy + ty * tile_meters
xmax = xmin + tile_meters
ymax = ymin + tile_meters
```

Expandir para a cidade inteira é só pedir mais tiles com `--tiles` ou `--bbox`.
Nenhum tile existente muda de posição.

---

## Dois fluxos de trabalho

### Fluxo 1 — Chão (TileMap no Godot)

```
ground_ref_X_Y.png  →  desenha tile GTA 2 por cima  →  tile_X_Y.png
                                                            ↓
                                                     TileMap no Godot 3
```

1. Abra `ground_ref_X_Y.png` no seu editor de imagem.
2. Desenhe o tile estilizado GTA 2 por cima (asfalto, calçadas, água, blocos).
3. Salve como `tile_X_Y.png`.
4. Monte o TileSet no Godot (ver seção Godot abaixo).

### Fluxo 2 — Prédios (Sprites com altura no Godot)

```
buildings_X_Y.json + buildings_ref_X_Y.png
        ↓
  desenha cada prédio como sprite (top-down, visão do teto)
        ↓
  Sprite2D no Godot com position = centroid_px, atributo height_m
        ↓
  (futuro) shader/script lê height_m e aplica parallax 2.5D
```

1. Abra `buildings_ref_X_Y.png` — cada footprint tem um número.
2. Número N no PNG = `buildings[N]` no JSON = `centroid_px` e `footprint_px`.
3. Desenhe o sprite de topo do prédio N.
4. No Godot, instancie o sprite com `position = centroid_px * world_scale`.
5. Grave `height_m` como metadado do sprite (variável exportada ou resource).

---

## Formato de `buildings_X_Y.json`

```json
{
  "tile": [0, 0],
  "origin_utm": [362752.0, 7346944.0],
  "tile_meters": 256.0,
  "tile_px": 256,
  "crs": "EPSG:31983",
  "m_per_level": 3.0,
  "buildings": [
    {
      "id": "way/123456789",
      "height_m": 12.0,
      "height_source": "osm_height",
      "levels": 4,
      "footprint_px": [[10.5, 20.3], [45.0, 20.3], [45.0, 60.1], [10.5, 60.1], [10.5, 20.3]],
      "centroid_px": [27.8, 40.2],
      "tags": {
        "building": "yes",
        "building:levels": "4",
        "height": "12",
        "name": "Edifício Exemplo"
      }
    }
  ]
}
```

**Campos:**

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | ID OSM (`way/N`) |
| `height_m` | float | Altura em metros |
| `height_source` | string | `"osm_height"` / `"osm_levels"` / `"default"` |
| `levels` | int\|null | Andares (null se não disponível) |
| `footprint_px` | `[[x,y],…]` | Polígono em pixels, origem topo-esquerdo do tile |
| `centroid_px` | `[x,y]` | Centro do footprint em pixels |
| `tags` | object | Tags OSM relevantes |

**Convenção de pixels**: `py=0` = borda norte do tile, `py=tile_px` = borda sul.
Mesma orientação do PNG (norte = topo).

---

## Importar no Godot 3

### TileMap (chão)

1. Copie os `tile_X_Y.png` para `res://assets/tiles/`.
2. Crie um recurso **TileSet** (`Project > New Resource > TileSet`).
3. Abra o editor TileSet, clique em `+` → **New Single Tile** para cada PNG.
   - Ou gere um spritesheet único e use **New Atlas** com Step = (tile_px, tile_px).
4. Salve como `map.tres`.
5. Adicione nó **TileMap** à cena.
6. Em `Tile Set`, selecione `map.tres`.
7. `Cell Size` = `(tile_px, tile_px)`.

> Godot 3 usa `TileSet + TileMap` (não `TileMapLayer`, que é Godot 4).

### Sprites de prédios

```gdscript
# Ao instanciar um prédio:
var building = BuildingSprite.instance()
building.position = Vector2(centroid_px.x, centroid_px.y) * WORLD_SCALE
building.height_m = data["height_m"]
add_child(building)
```

---

## Efeito 2.5D futuro (documentação do formato)

O efeito é **parallax por altura** calculado em tempo real — não pré-renderizado.

### Princípio

Quando a câmera se move, o topo de um prédio alto desliza mais do que o chão,
criando ilusão de volume. A fórmula:

```
deslocamento_topo = velocidade_camera * (height_m / REFERENCIA_ALTURA) * FATOR_PARALLAX
```

### Estrutura do sprite de prédio (preparar agora)

Cada prédio deve ter dois elementos:
- **Base**: sprite do topo do telhado, ancorado na posição `centroid_px` do chão.
- **Fachada** (opcional): sprite lateral, visível abaixo da base.

A âncora (`offset`) do sprite fica na borda **inferior** da imagem (base do prédio),
não no centro. Assim o deslocamento desliza apenas o topo.

### Script de parallax (esboço para implementar depois)

```gdscript
# BuildingSprite.gd
export var height_m: float = 9.0

const PARALLAX_FACTOR = 0.003  # ajuste por gameplay

func _process(_delta):
    var cam_offset = get_viewport().get_camera().offset
    # Topo do prédio desliza contra o movimento da câmera
    $Top.offset = -cam_offset * height_m * PARALLAX_FACTOR
```

### Por que `height_m` importa agora

O dado já está no `buildings_X_Y.json`. Ao desenhar os sprites e instanciá-los
no Godot com `height_m` como propriedade exportada, o efeito 2.5D é adicionado
depois com zero refatoração — só plug o script acima.

---

## Ajustar o visual de referência

Edite `GND` em `generate_grid.py`:

```python
GND = {
    "bg":          "#f5f5f0",   # fundo
    "water":       "#b8d4e8",   # água
    "park":        "#c8dcc8",   # parques
    "bld_fill":    "#dcdcd4",   # fill dos edifícios
    "bld_edge":    "#888880",   # borda dos edifícios
    "road_major":  "#1a1a1a",   # motorway/primary
    "road_mid":    "#555555",   # secondary/tertiary
    "road_minor":  "#888888",   # residential/service
    "road_foot":   "#bbbbbb",   # calçadas/ciclovias
}
```

Para apagar o cache e re-baixar dados OSM: `rm -rf output/cache/`.
