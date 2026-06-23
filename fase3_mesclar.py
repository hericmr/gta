#!/usr/bin/env python3
"""
fase3_mesclar.py - Fase 3: mescla altura (GEE) + area (UTM) nos footprints V3,
aplica correcoes manuais e gera maps/santos_buildings_2p5d.json.

Entrada:
  build/footprints_v3.geojson    (Fase 1)
  build/alturas_gee.geojson      (Fase 2)
  build/corrections.json         (opcional, criado manualmente)

Saida:
  maps/santos_buildings_2p5d.json

Nao sobrescreve maps/santos.json.

--- Formato de build/corrections.json ---
{
  "42": { "tipo": "offset", "delta_lon": 0.00008, "delta_lat": -0.00005 },
  "137": { "tipo": "substituir", "poly_lonlat": [[-46.334, -23.931], ...] },
  "291": { "tipo": "remover" }
}
A chave e o v3_idx (string) do edificio a corrigir.
"""

import json
import os
import sys

try:
    from shapely.geometry import Polygon
    from pyproj import Transformer
except ImportError:
    print("[ERRO] Dependencias ausentes. Rode: pip install shapely pyproj")
    sys.exit(1)

INPUT_FOOTPRINTS  = "build/footprints_v3.geojson"
INPUT_ALTURAS     = "build/alturas_gee.geojson"
INPUT_CORRECTIONS = "build/corrections.json"
OUTPUT            = "maps/santos_buildings_2p5d.json"

LAT_MIN = -23.995;  LAT_MAX = -23.905
LON_MIN = -46.380;  LON_MAX = -46.285
LARG_PX = 8000.0;   ALT_PX  = 8292.0
ESCALA  = 15.0

TRANSFORMER_UTM = Transformer.from_crs("EPSG:4326", "EPSG:31983", always_xy=True)

ALTURA_DEFAULT = {
    "house":       6.0,
    "residential": 6.0,
    "apartments":  24.0,
    "commercial":  8.0,
    "retail":      8.0,
    "industrial":  7.0,
    "warehouse":   7.0,
    "kiosk":       3.5,
    "roof":        4.0,
    "church":      12.0,
    "dormitory":   10.0,
    "school":      9.0,
    "yes":         8.0,
}
DEFAULT_GENERICO = 8.0
M_POR_ANDAR     = 3.0


def lonlat_para_game(lon, lat):
    x = (lon - LON_MIN) / (LON_MAX - LON_MIN) * LARG_PX * ESCALA
    y = (1.0 - (lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * ALT_PX * ESCALA
    return [round(x, 2), round(y, 2)]


def calcular_area_m2(coords_lonlat):
    coords_utm = [TRANSFORMER_UTM.transform(lon, lat) for lon, lat in coords_lonlat]
    poly = Polygon(coords_utm)
    return abs(poly.area)


def aplicar_offset(coords, delta_lon, delta_lat):
    return [[lon + delta_lon, lat + delta_lat] for lon, lat in coords]


def escolher_altura(props, height_2p5d):
    if height_2p5d is not None and height_2p5d > 2.0:
        return height_2p5d, "2p5d"

    osm_height = props.get("osm_height")
    if osm_height is not None and float(osm_height) > 2.0:
        return float(osm_height), "osm_height"

    osm_levels = props.get("osm_levels")
    if osm_levels is not None and int(osm_levels) > 0:
        return float(osm_levels) * M_POR_ANDAR, "levels"

    tipo = props.get("building", "yes")
    return ALTURA_DEFAULT.get(tipo, DEFAULT_GENERICO), "default"


def carregar_corrections():
    if not os.path.exists(INPUT_CORRECTIONS):
        return {}
    with open(INPUT_CORRECTIONS, encoding="utf-8") as f:
        data = json.load(f)
    print(f"[Fase 3] {len(data)} correcoes carregadas de {INPUT_CORRECTIONS}.")
    return data


def main():
    for caminho in [INPUT_FOOTPRINTS, INPUT_ALTURAS]:
        if not os.path.exists(caminho):
            script = "fase1_footprints.py" if "v3" in caminho else "fase2_gee_alturas.py"
            print(f"[ERRO] {caminho} nao encontrado. Rode {script} primeiro.")
            sys.exit(1)

    with open(INPUT_FOOTPRINTS, encoding="utf-8") as f:
        gj_fp = json.load(f)
    with open(INPUT_ALTURAS, encoding="utf-8") as f:
        gj_alt = json.load(f)

    corrections = carregar_corrections()

    # Indexar alturas por v3_idx
    alturas_por_idx = {}
    for ft in gj_alt["features"]:
        idx = ft["properties"].get("v3_idx")
        h   = ft["properties"].get("height_2p5d")
        if idx is not None:
            alturas_por_idx[idx] = h

    predios = []
    fontes  = {"2p5d": 0, "osm_height": 0, "levels": 0, "default": 0}
    removidos   = 0
    corrigidos  = 0

    for ft in gj_fp["features"]:
        props = ft["properties"]
        idx   = props["v3_idx"]
        chave = str(idx)

        coords = ft["geometry"]["coordinates"][0]

        # Aplicar correcoes manuais
        corr = corrections.get(chave)
        if corr:
            tipo_corr = corr.get("tipo")
            if tipo_corr == "remover":
                removidos += 1
                continue
            elif tipo_corr == "offset":
                coords = aplicar_offset(coords, corr["delta_lon"], corr["delta_lat"])
                corrigidos += 1
            elif tipo_corr == "substituir":
                coords = corr["poly_lonlat"]
                # Fechar o poligono se necessario
                if coords[0] != coords[-1]:
                    coords.append(coords[0])
                corrigidos += 1

        height_2p5d = alturas_por_idx.get(idx)
        altura_m, fonte = escolher_altura(props, height_2p5d)
        fontes[fonte] += 1

        area_m2 = calcular_area_m2(coords)
        andares = max(1, round(altura_m / M_POR_ANDAR))

        poly_game = [lonlat_para_game(lon, lat) for lon, lat in coords]

        predios.append({
            "v3_idx":       idx,
            "v3_id":        props.get("v3_id"),
            "confidence":   props.get("confidence"),
            "poly_game":    poly_game,
            "poly_lonlat":  coords,
            "altura_m":     round(altura_m, 2),
            "andares":      andares,
            "area_m2":      round(area_m2, 1),
            "altura_fonte": fonte,
        })

    output = {"predios": predios}
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, separators=(",", ":"))

    total = len(predios) + removidos
    print(f"\n[Fase 3] Concluida.")
    print(f"  Total de footprints : {total}")
    print(f"  Removidos (manual)  : {removidos}")
    print(f"  Corrigidos (manual) : {corrigidos}")
    print(f"  Predios na saida    : {len(predios)}")
    print(f"  Fontes de altura:")
    for fonte, n in fontes.items():
        pct = 100 * n / len(predios) if predios else 0
        print(f"    {fonte:12s}: {n:5d}  ({pct:.1f}%)")
    print(f"  Saida               : {OUTPUT}")
    if removidos + corrigidos == 0 and not os.path.exists(INPUT_CORRECTIONS):
        print(f"\n  Dica: crie {INPUT_CORRECTIONS} para corrigir poligonos deslocados.")
        print(f"  Veja o planning.md para o formato do arquivo.")


if __name__ == "__main__":
    main()
