#!/usr/bin/env python3
"""
baixar_tiles.py — Baixa tiles de satélite ESRI World Imagery para Santos-SP
e atualiza assets/tiles/meta.json

Uso:
  python3 baixar_tiles.py
"""

import json
import math
import os
import time
import sys
import urllib.request

ZOOM     = 18
TILE_DIR = "assets/tiles"
META     = "assets/tiles/meta.json"

# Cobertura: Santos do Valongo (norte) até Ponta da Praia (sul) + spawn
TX_MIN = 97328
TX_MAX = 97362   # 35 tiles leste-oeste
TY_MIN = 149028
TY_MAX = 149085  # 58 tiles norte-sul (estendido 2 tiles a mais para o sul)

ESPERA  = 0.15   # segundos entre requisições (respeita rate limit ESRI)

ESRI_URL = (
    "https://server.arcgisonline.com/ArcGIS/rest/services"
    "/World_Imagery/MapServer/tile/{z}/{y}/{x}"
)

HEADERS = {"User-Agent": "GTA-Santos-Game/1.0 (github.com/hericmr/gta)"}


def tile_to_lonlat(tx: int, ty: int, z: int):
    n = 2 ** z
    lon = tx / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * ty / n))))
    return lon, lat


def baixar_tile(tx: int, ty: int) -> bool:
    nome    = f"z{ZOOM}_{tx}_{ty}.png"
    caminho = os.path.join(TILE_DIR, nome)
    if os.path.exists(caminho):
        return False   # já existe

    url = ESRI_URL.format(z=ZOOM, y=ty, x=tx)
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            dados = r.read()
        with open(caminho, "wb") as f:
            f.write(dados)
        return True
    except Exception as e:
        print(f"  ERRO {tx},{ty}: {e}")
        return False


def atualizar_meta():
    lon_nw, lat_nw = tile_to_lonlat(TX_MIN, TY_MIN, ZOOM)
    lon_se, lat_se = tile_to_lonlat(TX_MAX + 1, TY_MAX + 1, ZOOM)

    # Dimensão em pixels — mantém mesma resolução dos tiles existentes
    n_tiles_x = TX_MAX - TX_MIN + 1
    n_tiles_y = TY_MAX - TY_MIN + 1
    larg_px   = n_tiles_x * 256
    alt_px    = n_tiles_y * 256

    meta = {
        "zoom":           ZOOM,
        "tile_px":        256,
        "tx_min":         TX_MIN,
        "ty_min":         TY_MIN,
        "tx_max":         TX_MAX,
        "ty_max":         TY_MAX,
        "bbox":           [round(lat_se, 6), round(lon_nw, 6),
                           round(lat_nw, 6), round(lon_se, 6)],
        "largura_map_px": larg_px,
        "altura_map_px":  alt_px,
    }
    with open(META, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"\n[META] Salvo: bbox lat [{lat_se:.5f}, {lat_nw:.5f}]  "
          f"lon [{lon_nw:.5f}, {lon_se:.5f}]")
    print(f"       Mapa: {larg_px} x {alt_px} px")


def main():
    os.makedirs(TILE_DIR, exist_ok=True)

    total    = (TX_MAX - TX_MIN + 1) * (TY_MAX - TY_MIN + 1)
    ja_tem   = sum(
        1 for tx in range(TX_MIN, TX_MAX + 1)
          for ty in range(TY_MIN, TY_MAX + 1)
          if os.path.exists(os.path.join(TILE_DIR, f"z{ZOOM}_{tx}_{ty}.png"))
    )
    a_baixar = total - ja_tem

    print(f"Tiles no grid {TX_MAX-TX_MIN+1}x{TY_MAX-TY_MIN+1}: {total}")
    print(f"  Já existem: {ja_tem}")
    print(f"  A baixar:   {a_baixar}")
    if a_baixar == 0:
        print("Tudo já baixado.")
        atualizar_meta()
        return

    baixados = 0
    erros    = 0
    for ty in range(TY_MIN, TY_MAX + 1):
        for tx in range(TX_MIN, TX_MAX + 1):
            ok = baixar_tile(tx, ty)
            if ok:
                baixados += 1
                prog = baixados / a_baixar * 100
                print(f"\r  {baixados}/{a_baixar} ({prog:.0f}%)  último: {tx},{ty}  ",
                      end="", flush=True)
                time.sleep(ESPERA)
        sys.stdout.flush()

    print(f"\n[OK] Baixados: {baixados}  Erros: {erros}")
    atualizar_meta()
    print("\nReinicie o Godot para os tiles aparecerem.")


if __name__ == "__main__":
    main()
