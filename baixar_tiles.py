#!/usr/bin/env python3
"""
baixar_tiles.py — Baixa tiles de satélite (ESRI World Imagery, zoom 18)
e salva individualmente em assets/tiles/ para o sistema de streaming do Godot 3.

Uso:
    python3 baixar_tiles.py

Dependência: pip3 install Pillow
"""

import io
import json
import math
import os
import time
import urllib.request
from PIL import Image

# ── Configuração ────────────────────────────────────────────────────────────

# Bbox do mapa (deve bater com importar_santos.py)
BBOX = (-23.995, -46.38, -23.905, -46.285)

ZOOM = 18

# OpenStreetMap padrão
TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
TILE_PX   = 256

TILES_DIR  = "assets/tiles"
META_FILE  = "assets/tiles/meta.json"

LARGURA_MAP_PX = 8000

# Range fixo de tiles (região do spawn — não calcular da bbox inteira)
TX_MIN, TX_MAX = 97347, 97355
TY_MIN, TY_MAX = 149066, 149074


# ── Funções geográficas ─────────────────────────────────────────────────────

def ll_to_tile(lat, lon, zoom):
    n  = 2 ** zoom
    tx = int((lon + 180) / 360 * n)
    lr = math.radians(lat)
    ty = int((1 - math.log(math.tan(lr) + 1 / math.cos(lr)) / math.pi) / 2 * n)
    return tx, ty

def tile_to_ll(tx, ty, zoom):
    n   = 2 ** zoom
    lon = tx / n * 360 - 180
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * ty / n))))
    return lat, lon

def calcular_altura_map():
    min_lat, min_lon, max_lat, max_lon = BBOX
    cos_lat = math.cos(math.radians((min_lat + max_lat) / 2))
    razao   = (max_lon - min_lon) * cos_lat / (max_lat - min_lat)
    return int(LARGURA_MAP_PX / razao)


# ── Download ────────────────────────────────────────────────────────────────

def baixar_tile(tx, ty, zoom):
    path = os.path.join(TILES_DIR, f"z{zoom}_{tx}_{ty}.png")
    if os.path.exists(path):
        return True  # cache
    url = TILE_URL.format(z=zoom, x=tx, y=ty)
    req = urllib.request.Request(url, headers={"User-Agent": "santos-driver/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = r.read()
        img = Image.open(io.BytesIO(data)).convert("RGB")
        img.save(path, optimize=True)
        return True
    except Exception as e:
        print(f"\n  ⚠ falha {tx},{ty}: {e}")
        return False


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(TILES_DIR, exist_ok=True)

    min_lat, min_lon, max_lat, max_lon = BBOX
    altura_map_px = calcular_altura_map()

    tx_min, tx_max = TX_MIN, TX_MAX
    ty_min, ty_max = TY_MIN, TY_MAX

    nx    = tx_max - tx_min + 1
    ny    = ty_max - ty_min + 1
    total = nx * ny

    print(f"Zoom {ZOOM}: {nx}×{ny} = {total} tiles")

    # Conta cache
    ja_baixados = sum(
        1 for ty in range(ty_min, ty_max + 1)
          for tx in range(tx_min, tx_max + 1)
          if os.path.exists(os.path.join(TILES_DIR, f"z{ZOOM}_{tx}_{ty}.png"))
    )
    print(f"Cache: {ja_baixados}/{total} já existem")

    baixados = 0
    novos    = 0
    for ty in range(ty_min, ty_max + 1):
        for tx in range(tx_min, tx_max + 1):
            ok = baixar_tile(tx, ty, ZOOM)
            baixados += 1
            if ok:
                novos += 1
            print(f"\r  {baixados}/{total} ({100*baixados//total}%)", end="", flush=True)
            time.sleep(0.03)

    print(f"\n{novos} tiles salvos em {TILES_DIR}/")

    # Meta: informações que o Godot precisa para posicionar cada tile
    meta = {
        "zoom":           ZOOM,
        "tile_px":        TILE_PX,
        "tx_min":         tx_min,
        "ty_min":         ty_min,
        "tx_max":         tx_max,
        "ty_max":         ty_max,
        "bbox":           list(BBOX),
        "largura_map_px": LARGURA_MAP_PX,
        "altura_map_px":  altura_map_px
    }
    with open(META_FILE, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"Meta salvo em {META_FILE}")


if __name__ == "__main__":
    main()
