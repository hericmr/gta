#!/usr/bin/env python3
"""
Baixa tiles do OpenStreetMap e monta uma imagem de referência da área.
Use como guia visual para desenhar os tiles do jogo.
"""

import argparse
import math
from pathlib import Path

import requests
from PIL import Image

TILE_SERVER = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
HEADERS = {"User-Agent": "santos-driver-game-reference/1.0"}
TILE_PX = 256  # tiles OSM são sempre 256x256


def lat_lon_to_tile(lat, lon, zoom):
    n = 2 ** zoom
    x = int((lon + 180) / 360 * n)
    y = int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)
    return x, y


def tile_to_lat_lon(x, y, zoom):
    n = 2 ** zoom
    lon = x / n * 360 - 180
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    return lat, lon


def download_tile(z, x, y, cache_dir) -> Image.Image:
    path = cache_dir / f"{z}_{x}_{y}.png"
    if path.exists():
        return Image.open(path).convert("RGBA")
    url = TILE_SERVER.format(z=z, x=x, y=y)
    r = requests.get(url, headers=HEADERS, timeout=15)
    r.raise_for_status()
    path.write_bytes(r.content)
    return Image.open(path).convert("RGBA")


def main():
    p = argparse.ArgumentParser(description="Baixa mapa OSM como referência visual.")
    p.add_argument("--lat",  type=float, default=-23.9608, help="Latitude do centro.")
    p.add_argument("--lon",  type=float, default=-46.3322, help="Longitude do centro.")
    p.add_argument("--zoom", type=int,   default=17,       help="Zoom OSM (15=bairro, 17=rua, 18=detalhe).")
    p.add_argument("--raio", type=int,   default=2,        help="Tiles ao redor do centro (default 2 = 5x5).")
    p.add_argument("--out",  type=Path,  default=Path("output/referencia_osm.png"))
    args = p.parse_args()

    cache = args.out.parent / "cache_osm"
    cache.mkdir(parents=True, exist_ok=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    cx, cy = lat_lon_to_tile(args.lat, args.lon, args.zoom)
    r = args.raio

    x_min, x_max = cx - r, cx + r
    y_min, y_max = cy - r, cy + r
    cols = x_max - x_min + 1
    rows = y_max - y_min + 1

    canvas = Image.new("RGBA", (cols * TILE_PX, rows * TILE_PX))

    print(f"Baixando {cols}x{rows} = {cols*rows} tiles (zoom {args.zoom})...")
    for row, ty in enumerate(range(y_min, y_max + 1)):
        for col, tx in enumerate(range(x_min, x_max + 1)):
            print(f"  {tx},{ty}...", end=" ", flush=True)
            img = download_tile(args.zoom, tx, ty, cache)
            canvas.paste(img, (col * TILE_PX, row * TILE_PX))
    print()

    # Marca o centro com uma cruz vermelha
    from PIL import ImageDraw
    draw = ImageDraw.Draw(canvas)
    cx_px = r * TILE_PX + TILE_PX // 2
    cy_px = r * TILE_PX + TILE_PX // 2
    draw.line([(cx_px - 15, cy_px), (cx_px + 15, cy_px)], fill=(255, 0, 0, 200), width=2)
    draw.line([(cx_px, cy_px - 15), (cx_px, cy_px + 15)], fill=(255, 0, 0, 200), width=2)

    canvas.save(str(args.out))

    lat_nw, lon_nw = tile_to_lat_lon(x_min, y_min, args.zoom)
    lat_se, lon_se = tile_to_lat_lon(x_max + 1, y_max + 1, args.zoom)
    print(f"Salvo: {args.out}  ({canvas.width}x{canvas.height}px)")
    print(f"Área: {lat_se:.5f},{lon_nw:.5f} → {lat_nw:.5f},{lon_se:.5f}")


if __name__ == "__main__":
    main()
