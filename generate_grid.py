#!/usr/bin/env python3
"""
generate_grid.py — Grade determinística de tiles de referência para Santos/SP.

Por tile gera:
  ground_ref_<tx>_<ty>.png   — referência do chão (ruas, água, contornos)
  buildings_<tx>_<ty>.json   — footprints + altura dos prédios
  buildings_ref_<tx>_<ty>.png — visualização dos footprints numerados
  grid.json                   — manifesto da grade (origem, escala, tiles gerados)

Projeção: EPSG:31983 (SIRGAS 2000 / UTM Zone 23S)
"""

import argparse
import json
import math
import os
import sys
import tempfile
import time
from pathlib import Path

import geopandas as gpd
import matplotlib
import matplotlib.pyplot as plt
import pandas as pd
import requests
from PIL import Image
from pyproj import Transformer
from shapely.geometry import box as shapely_box, Polygon, LineString

matplotlib.use("Agg")

# ── Projeção ──────────────────────────────────────────────────────────────────

CRS_UTM = "EPSG:31983"
CRS_GEO = "EPSG:4326"

_to_utm = Transformer.from_crs(CRS_GEO, CRS_UTM, always_xy=True)
_to_geo = Transformer.from_crs(CRS_UTM, CRS_GEO, always_xy=True)

# ── Paleta de referência (sketch limpo, fácil de rastrear à mão) ──────────────

GND = {
    "bg":          "#f5f5f0",
    "water":       "#b8d4e8",
    "park":        "#c8dcc8",
    "bld_fill":    "#dcdcd4",
    "bld_edge":    "#888880",
    "road_major":  "#1a1a1a",
    "road_mid":    "#555555",
    "road_minor":  "#888888",
    "road_foot":   "#bbbbbb",
}

# Cores distintas para os footprints na imagem de referência de prédios
BLD_COLORS = [
    "#e8d4c8", "#c8d4e8", "#d4e8c8", "#e8e0c8", "#d4c8e8",
    "#e8c8d4", "#c8e8d8", "#d8d4e8", "#e8d8c8", "#c8dce8",
]

# Hierarquia de vias: chave_paleta, largura_pt
ROAD_STYLE = {
    "motorway":       ("road_major", 3.0),
    "motorway_link":  ("road_major", 1.8),
    "trunk":          ("road_major", 2.8),
    "trunk_link":     ("road_major", 1.6),
    "primary":        ("road_major", 2.5),
    "primary_link":   ("road_major", 1.4),
    "secondary":      ("road_mid",   2.0),
    "secondary_link": ("road_mid",   1.2),
    "tertiary":       ("road_mid",   1.6),
    "tertiary_link":  ("road_mid",   1.0),
    "residential":    ("road_minor", 1.2),
    "unclassified":   ("road_minor", 1.0),
    "living_street":  ("road_minor", 1.0),
    "service":        ("road_minor", 0.8),
    "pedestrian":     ("road_foot",  0.7),
    "footway":        ("road_foot",  0.5),
    "path":           ("road_foot",  0.4),
    "cycleway":       ("road_foot",  0.4),
    "steps":          ("road_foot",  0.3),
}
ROAD_ORDER = list(ROAD_STYLE.keys())
ROAD_DEFAULT = ("road_minor", 0.8)

M_PER_LEVEL = 3.0
RENDER_DPI  = 96


# ── Matemática da grade ───────────────────────────────────────────────────────

def init_origin(lat: float, lon: float, tile_m: float) -> tuple:
    """lat/lon → UTM, arredonda para múltiplo de tile_m (ancora da grade)."""
    x, y = _to_utm.transform(lon, lat)
    return math.floor(x / tile_m) * tile_m, math.floor(y / tile_m) * tile_m


def tile_bbox_utm(tx: int, ty: int, ox: float, oy: float, tile_m: float) -> tuple:
    """(xmin, ymin, xmax, ymax) em metros UTM para o tile (tx, ty)."""
    xmin = ox + tx * tile_m
    ymin = oy + ty * tile_m
    return xmin, ymin, xmin + tile_m, ymin + tile_m


def bbox_utm_to_geo(xmin, ymin, xmax, ymax) -> tuple:
    """Bbox UTM → (south, west, north, east) WGS84."""
    lons, lats = [], []
    for x in (xmin, xmax):
        for y in (ymin, ymax):
            lon, lat = _to_geo.transform(x, y)
            lons.append(lon); lats.append(lat)
    return min(lats), min(lons), max(lats), max(lons)


def tiles_from_bbox_geo(south, west, north, east, ox, oy, tile_m) -> list:
    """Lista de (tx, ty) que cobrem o bbox WGS84."""
    xs, ys = [], []
    for lat in (south, north):
        for lon in (west, east):
            x, y = _to_utm.transform(lon, lat)
            xs.append(x); ys.append(y)
    tx_min = math.floor((min(xs) - ox) / tile_m)
    tx_max = math.floor((max(xs) - ox) / tile_m)
    ty_min = math.floor((min(ys) - oy) / tile_m)
    ty_max = math.floor((max(ys) - oy) / tile_m)
    return [(tx, ty)
            for ty in range(ty_min, ty_max + 1)
            for tx in range(tx_min, tx_max + 1)]


def utm_to_px(x, y, xmin, ymax, tile_m, tile_px) -> tuple:
    """Ponto UTM → pixel relativo ao tile (origem = topo-esquerdo / norte-oeste)."""
    return (
        round((x - xmin) / tile_m * tile_px, 1),
        round((ymax - y) / tile_m * tile_px, 1),   # Y invertido: norte = topo
    )


# ── Download e cache ──────────────────────────────────────────────────────────

def _ck(tx, ty): return f"{tx}_{ty}"


def download_roads(south, west, north, east, tx, ty, cache_dir) -> gpd.GeoDataFrame:
    cp = cache_dir / f"roads_{_ck(tx,ty)}.gpkg"
    if cp.exists():
        return gpd.read_file(cp)
    try:
        import osmnx as ox
        poly = shapely_box(west, south, east, north)
        G = ox.graph_from_polygon(poly, network_type="all", retain_all=False)
        _, edges = ox.graph_to_gdfs(G)
        edges = edges.reset_index()
        edges["highway"] = edges["highway"].apply(
            lambda v: v[0] if isinstance(v, list) else v
        )
        gdf = edges.to_crs(CRS_UTM)
        gdf.to_file(cp, driver="GPKG")
        return gdf
    except Exception as e:
        print(f"    Aviso ruas: {e}")
        return gpd.GeoDataFrame(geometry=[], crs=CRS_UTM)


def overpass_fetch(query: str, retries: int = 3) -> list:
    url = "https://overpass-api.de/api/interpreter"
    for attempt in range(retries):
        try:
            r = requests.post(url, data={"data": query}, timeout=120)
            r.raise_for_status()
            return r.json().get("elements", [])
        except Exception as e:
            if attempt < retries - 1:
                wait = 10 * (attempt + 1)
                print(f"    Overpass erro ({e}), aguardando {wait}s...")
                time.sleep(wait)
            else:
                print(f"    Overpass falhou definitivamente: {e}")
                return []


def elements_to_gdf(elements: list) -> gpd.GeoDataFrame:
    """Ways Overpass com geometry → GeoDataFrame em CRS_UTM."""
    rows = []
    for el in elements:
        if el.get("type") != "way" or "geometry" not in el:
            continue
        coords = [(p["lon"], p["lat"]) for p in el["geometry"]]
        if len(coords) < 3:
            continue
        try:
            geom = Polygon(coords)
            if not geom.is_valid:
                geom = geom.buffer(0)
        except Exception:
            geom = LineString(coords)
        tags = el.get("tags", {})
        rows.append({"geometry": geom, **tags})
    if not rows:
        return gpd.GeoDataFrame(geometry=[], crs=CRS_UTM)
    return gpd.GeoDataFrame(rows, crs=CRS_GEO).to_crs(CRS_UTM)


def fetch_polys(south, west, north, east, tag_filter, name, tx, ty, cache_dir) -> list:
    cp = cache_dir / f"{name}_{_ck(tx,ty)}.json"
    if cp.exists():
        return json.loads(cp.read_text())
    bbox_s = f"{south},{west},{north},{east}"
    q = f"[out:json][timeout:90];\n(way[{tag_filter}]({bbox_s}););\nout body geom;"
    els = overpass_fetch(q)
    cp.write_text(json.dumps(els))
    return els


def download_water(south, west, north, east, tx, ty, cache_dir) -> gpd.GeoDataFrame:
    specs = [
        ('"natural"="water"',                       "water_nat"),
        ('"waterway"~"river|canal|dock|tidal_channel"', "waterway"),
        ('"landuse"~"reservoir|basin"',             "water_lu"),
        ('"harbour"="yes"',                         "harbour"),
    ]
    gdfs = []
    for f, n in specs:
        els = fetch_polys(south, west, north, east, f, n, tx, ty, cache_dir)
        g = elements_to_gdf(els)
        if not g.empty:
            gdfs.append(g)
    if not gdfs:
        return gpd.GeoDataFrame(geometry=[], crs=CRS_UTM)
    return gpd.GeoDataFrame(pd.concat(gdfs, ignore_index=True), crs=CRS_UTM)


def download_parks(south, west, north, east, tx, ty, cache_dir) -> gpd.GeoDataFrame:
    specs = [
        ('"leisure"~"park|garden|pitch|playground"',         "park_lei"),
        ('"landuse"~"grass|forest|recreation_ground|cemetery"', "park_lu"),
        ('"natural"~"wood|scrub|heath|grassland"',           "park_nat"),
    ]
    gdfs = []
    for f, n in specs:
        els = fetch_polys(south, west, north, east, f, n, tx, ty, cache_dir)
        g = elements_to_gdf(els)
        if not g.empty:
            gdfs.append(g)
    if not gdfs:
        return gpd.GeoDataFrame(geometry=[], crs=CRS_UTM)
    return gpd.GeoDataFrame(pd.concat(gdfs, ignore_index=True), crs=CRS_UTM)


def download_buildings(south, west, north, east, tx, ty, cache_dir) -> list:
    """Retorna elementos Overpass brutos (com tags de altura)."""
    cp = cache_dir / f"buildings_{_ck(tx,ty)}.json"
    if cp.exists():
        return json.loads(cp.read_text())
    bbox_s = f"{south},{west},{north},{east}"
    q = f"[out:json][timeout:90];\n(way[building]({bbox_s}););\nout body geom;"
    els = overpass_fetch(q)
    cp.write_text(json.dumps(els))
    return els


# ── Extração de altura ────────────────────────────────────────────────────────

def extract_height(tags: dict, default_levels: int) -> dict:
    if "height" in tags:
        try:
            h = float(str(tags["height"]).split()[0].replace(",", "."))
            lvl = tags.get("building:levels")
            return {"height_m": h, "height_source": "osm_height",
                    "levels": int(lvl) if lvl else None}
        except (ValueError, AttributeError):
            pass
    if "building:levels" in tags:
        try:
            lvl = int(tags["building:levels"])
            return {"height_m": round(lvl * M_PER_LEVEL, 1),
                    "height_source": "osm_levels", "levels": lvl}
        except ValueError:
            pass
    return {"height_m": round(default_levels * M_PER_LEVEL, 1),
            "height_source": "default", "levels": default_levels}


# ── Clipe ao tile ─────────────────────────────────────────────────────────────

def clip(gdf, xmin, ymin, xmax, ymax) -> gpd.GeoDataFrame:
    if gdf is None or gdf.empty:
        return gdf
    try:
        return gdf.clip(shapely_box(xmin, ymin, xmax, ymax))
    except Exception:
        b = shapely_box(xmin, ymin, xmax, ymax)
        return gdf[gdf.intersects(b)]


# ── Salvar figura como PNG de tamanho exato ───────────────────────────────────

def save_exact(fig, path, tile_px):
    """Salva figura e garante tile_px×tile_px com Pillow (fallback resize)."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
    fig.savefig(tmp_path, dpi=RENDER_DPI, bbox_inches=None, pad_inches=0)
    img = Image.open(tmp_path).convert("RGBA")
    if img.size != (tile_px, tile_px):
        img = img.resize((tile_px, tile_px), Image.LANCZOS)
    img.save(str(path), format="PNG")
    os.unlink(tmp_path)


# ── Renderização do chão ──────────────────────────────────────────────────────

def make_axes(tile_px, xmin, ymin, xmax, ymax, bg):
    fig = plt.figure(figsize=(tile_px / RENDER_DPI, tile_px / RENDER_DPI),
                     dpi=RENDER_DPI)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.patch.set_facecolor(bg)
    ax.set_facecolor(bg)
    return fig, ax


def render_ground_ref(roads, water, parks, buildings_gdf, bbox_utm, tile_px, path):
    xmin, ymin, xmax, ymax = bbox_utm
    fig, ax = make_axes(tile_px, xmin, ymin, xmax, ymax, GND["bg"])

    def plot_poly(gdf, color, zorder, ec=None):
        if gdf is None or gdf.empty:
            return
        g = clip(gdf, xmin, ymin, xmax, ymax)
        if g is None or g.empty:
            return
        kw = {"ax": ax, "color": color, "zorder": zorder,
              "edgecolor": ec or color, "linewidth": 0.4}
        g.plot(**kw)

    plot_poly(water, GND["water"], 1)
    plot_poly(parks, GND["park"],  2)

    if buildings_gdf is not None and not buildings_gdf.empty:
        b = clip(buildings_gdf, xmin, ymin, xmax, ymax)
        if not b.empty:
            b.plot(ax=ax, color=GND["bld_fill"], edgecolor=GND["bld_edge"],
                   linewidth=0.5, zorder=3)

    if roads is not None and not roads.empty:
        r = clip(roads, xmin, ymin, xmax, ymax)
        if not r.empty:
            for hw in ROAD_ORDER:
                sub = r[r["highway"] == hw]
                if sub.empty:
                    continue
                ck, lw = ROAD_STYLE[hw]
                sub.plot(ax=ax, color=GND[ck], linewidth=lw, zorder=4,
                         capstyle="round", joinstyle="round")
            other = r[~r["highway"].isin(ROAD_ORDER)]
            if not other.empty:
                other.plot(ax=ax, color=GND[ROAD_DEFAULT[0]],
                           linewidth=ROAD_DEFAULT[1], zorder=4)

    save_exact(fig, path, tile_px)
    plt.close(fig)


def render_buildings_ref(buildings_gdf, bbox_utm, tile_px, path):
    """Footprints coloridos e numerados (índice = posição no JSON)."""
    xmin, ymin, xmax, ymax = bbox_utm
    fig, ax = make_axes(tile_px, xmin, ymin, xmax, ymax, "#ffffff")

    if buildings_gdf is not None and not buildings_gdf.empty:
        b = clip(buildings_gdf, xmin, ymin, xmax, ymax)
        if not b.empty:
            for i, (_, row) in enumerate(b.iterrows()):
                color = BLD_COLORS[i % len(BLD_COLORS)]
                gpd.GeoDataFrame([row], crs=b.crs).plot(
                    ax=ax, color=color, edgecolor="#333333", linewidth=0.8, zorder=1)
                c = row.geometry.centroid
                ax.text(c.x, c.y, str(i), fontsize=4, ha="center", va="center",
                        color="#222222", zorder=2)

    save_exact(fig, path, tile_px)
    plt.close(fig)


# ── Export buildings JSON ─────────────────────────────────────────────────────

def export_buildings_json(elements, bbox_utm, tile_m, tile_px, tx, ty,
                           ox_, oy_, default_levels, path) -> gpd.GeoDataFrame:
    xmin, ymin, xmax, ymax = bbox_utm
    tile_box = shapely_box(xmin, ymin, xmax, ymax)
    out = []
    geoms = []

    for el in elements:
        if el.get("type") != "way" or "geometry" not in el:
            continue
        raw = el["geometry"]
        if len(raw) < 3:
            continue
        lons = [p["lon"] for p in raw]
        lats = [p["lat"] for p in raw]
        xs, ys = _to_utm.transform(lons, lats)
        try:
            poly = Polygon(zip(xs, ys))
            if not poly.is_valid:
                poly = poly.buffer(0)
        except Exception:
            continue
        if poly.is_empty or not poly.intersects(tile_box):
            continue

        clipped = poly.intersection(tile_box)
        if clipped.is_empty:
            continue

        tags = el.get("tags", {})
        h = extract_height(tags, default_levels)

        # Footprint em pixels do polígono recortado
        if hasattr(clipped, "exterior"):
            ring = list(clipped.exterior.coords)
        else:
            ring = list(max(clipped.geoms, key=lambda g: g.area).exterior.coords)

        footprint_px = [list(utm_to_px(x, y, xmin, ymax, tile_m, tile_px))
                        for x, y in ring]
        cx, cy = clipped.centroid.x, clipped.centroid.y
        centroid_px = list(utm_to_px(cx, cy, xmin, ymax, tile_m, tile_px))

        keep_tags = {k: tags[k] for k in
                     ("building", "building:levels", "height", "name",
                      "amenity", "addr:street") if k in tags}

        out.append({
            "id": f"way/{el['id']}",
            **h,
            "footprint_px": footprint_px,
            "centroid_px": centroid_px,
            "tags": keep_tags,
        })
        geoms.append({"geometry": poly})

    payload = {
        "tile": [tx, ty],
        "origin_utm": [ox_, oy_],
        "tile_meters": tile_m,
        "tile_px": tile_px,
        "crs": CRS_UTM,
        "m_per_level": M_PER_LEVEL,
        "buildings": out,
    }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False))

    if geoms:
        return gpd.GeoDataFrame(geoms, crs=CRS_UTM)
    return gpd.GeoDataFrame(geometry=[], crs=CRS_UTM)


# ── Manifesto grid.json ───────────────────────────────────────────────────────

def load_grid(grid_path, tile_m, tile_px, lat, lon) -> dict:
    if grid_path.exists():
        return json.loads(grid_path.read_text())
    ox_, oy_ = init_origin(lat, lon, tile_m)
    grid = {"origin_utm": [ox_, oy_], "crs": CRS_UTM,
            "tile_meters": tile_m, "tile_px": tile_px,
            "ref_lat": lat, "ref_lon": lon, "tiles": {}}
    grid_path.write_text(json.dumps(grid, indent=2))
    return grid


def save_grid(grid, grid_path):
    grid_path.write_text(json.dumps(grid, indent=2))


# ── Processamento de um tile ──────────────────────────────────────────────────

def process_tile(tx, ty, grid, args, cache_dir, out_dir):
    tile_m  = grid["tile_meters"]
    tile_px = grid["tile_px"]
    ox_, oy_ = grid["origin_utm"]

    bbox_utm = tile_bbox_utm(tx, ty, ox_, oy_, tile_m)
    xmin, ymin, xmax, ymax = bbox_utm
    south, west, north, east = bbox_utm_to_geo(xmin, ymin, xmax, ymax)

    print(f"  UTM [{xmin:.0f},{ymin:.0f}]→[{xmax:.0f},{ymax:.0f}]  "
          f"Geo S={south:.5f} W={west:.5f} N={north:.5f} E={east:.5f}")

    print("    ruas...",     end=" ", flush=True)
    roads = download_roads(south, west, north, east, tx, ty, cache_dir)
    print("ok")

    print("    água...",     end=" ", flush=True)
    water = download_water(south, west, north, east, tx, ty, cache_dir)
    print("ok")

    print("    parques...",  end=" ", flush=True)
    parks = download_parks(south, west, north, east, tx, ty, cache_dir)
    print("ok")

    print("    edifícios...", end=" ", flush=True)
    bld_els = download_buildings(south, west, north, east, tx, ty, cache_dir)
    print(f"{len(bld_els)} elementos")

    bld_json = out_dir / f"buildings_{tx}_{ty}.json"
    buildings_gdf = export_buildings_json(
        bld_els, bbox_utm, tile_m, tile_px, tx, ty,
        ox_, oy_, args.default_building_height, bld_json)
    n_bld = len(json.loads(bld_json.read_text())["buildings"])
    print(f"    {n_bld} prédios → {bld_json.name}")

    ground_path = out_dir / f"ground_ref_{tx}_{ty}.png"
    print(f"    render chão → {ground_path.name}")
    render_ground_ref(roads, water, parks, buildings_gdf, bbox_utm, tile_px, ground_path)

    bld_ref_path = out_dir / f"buildings_ref_{tx}_{ty}.png"
    print(f"    render prédios → {bld_ref_path.name}")
    render_buildings_ref(buildings_gdf, bbox_utm, tile_px, bld_ref_path)

    return {
        "ground_ref": ground_path.name,
        "buildings_json": bld_json.name,
        "buildings_ref": bld_ref_path.name,
        "bbox_utm": list(bbox_utm),
        "bbox_geo": [south, west, north, east],
        "n_buildings": n_bld,
    }


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(
        description="Grade de tiles de referência para Santos/SP (estilo GTA 2).")
    area = p.add_mutually_exclusive_group()
    area.add_argument("--tiles", nargs="+", metavar="TX,TY",
                      help="Tiles específicos, ex: 0,0 1,0 0,-1")
    area.add_argument("--bbox", nargs=4, metavar=("S","W","N","E"), type=float,
                      help="Gera tiles cobrindo o bbox WGS84.")
    p.add_argument("--tile-meters",  type=float, default=256.0)
    p.add_argument("--tile-px",      type=int,   default=256)
    p.add_argument("--out-dir",      type=Path,  default=Path("output"))
    p.add_argument("--default-building-height", type=int, default=3,
                   help="Andares padrão quando OSM não informa (default: 3).")
    p.add_argument("--ref-lat", type=float, default=-23.9608)
    p.add_argument("--ref-lon", type=float, default=-46.3322)
    return p.parse_args()


def main():
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    cache_dir = args.out_dir / "cache"
    cache_dir.mkdir(exist_ok=True)

    grid_path = args.out_dir / "grid.json"
    grid = load_grid(grid_path, args.tile_meters, args.tile_px,
                     args.ref_lat, args.ref_lon)

    if (grid["tile_meters"] != args.tile_meters or
            grid["tile_px"] != args.tile_px):
        print("ERRO: grid.json existente tem parâmetros diferentes.")
        print(f"  grade: {grid['tile_meters']}m, {grid['tile_px']}px")
        print(f"  pedido: {args.tile_meters}m, {args.tile_px}px")
        sys.exit(1)

    ox_, oy_ = grid["origin_utm"]

    if args.tiles:
        tiles = [tuple(int(v) for v in t.split(",")) for t in args.tiles]
    elif args.bbox:
        s, w, n, e = args.bbox
        tiles = tiles_from_bbox_geo(s, w, n, e, ox_, oy_, grid["tile_meters"])
        print(f"bbox → {len(tiles)} tiles: {tiles}")
    else:
        tiles = [(0, 0)]
        print("Nenhuma área especificada → tile (0,0) — centro de Santos.")

    print(f"\nOrigem UTM: {grid['origin_utm']}")
    print(f"Grade: {grid['tile_meters']}m/tile, {grid['tile_px']}px/tile\n")

    for tx, ty in tiles:
        print(f"\n[Tile {tx},{ty}]")
        result = process_tile(tx, ty, grid, args, cache_dir, args.out_dir)
        grid["tiles"][f"{tx},{ty}"] = result
        save_grid(grid, grid_path)

    print(f"\nManifesto: {grid_path}  ({len(grid['tiles'])} tiles)")


if __name__ == "__main__":
    main()
