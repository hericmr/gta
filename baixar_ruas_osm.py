#!/usr/bin/env python3
"""
baixar_ruas_osm.py — Baixa ruas + footprints OSM via Overpass e gera maps/santos.json
com o mesmo sistema de coordenadas do meta.json atual.

Uso:
  python3 baixar_ruas_osm.py
"""
import json, math, os, sys, time
import urllib.request, urllib.parse

META        = "assets/tiles/meta.json"
OUTPUT      = "maps/santos.json"
CACHE_RUAS  = "build/ruas_osm_raw.json"

LARGURA_PAD = {
    "motorway": 14, "trunk": 12, "primary": 10, "secondary": 8,
    "tertiary": 6,  "residential": 5, "service": 3, "unclassified": 4,
    "living_street": 3, "footway": 2, "cycleway": 2, "path": 2,
}
LARGURA_DEFAULT = 4

HEADERS = {"User-Agent": "GTA-Santos-Game/1.0"}


def carregar_meta():
    with open(META) as f:
        m = json.load(f)
    bbox = m["bbox"]  # [lat_min, lon_min, lat_max, lon_max]
    return {
        "lat_min": bbox[0], "lon_min": bbox[1],
        "lat_max": bbox[2], "lon_max": bbox[3],
        "larg":    m["largura_map_px"],
        "alt":     m["altura_map_px"],
    }


def lonlat_para_px(lon, lat, m):
    x = (lon - m["lon_min"]) / (m["lon_max"] - m["lon_min"]) * m["larg"]
    y = (1.0 - (lat - m["lat_min"]) / (m["lat_max"] - m["lat_min"])) * m["alt"]
    return [round(x, 1), round(y, 1)]


def baixar_overpass(m):
    bbox_q = f"{m['lat_min']},{m['lon_min']},{m['lat_max']},{m['lon_max']}"
    query = (
        f"[out:json][timeout:120];"
        f"("
        f"  way[highway][highway!~\"proposed|construction|abandoned|platform\"]({bbox_q});"
        f"  way[building]({bbox_q});"
        f");"
        f"out geom tags;"
    )
    print("[OSM] Baixando ruas + prédios do Overpass...")
    data = urllib.parse.urlencode({"data": query}).encode()
    req  = urllib.request.Request(
        "https://overpass-api.de/api/interpreter", data=data, headers=HEADERS
    )
    for tentativa in range(3):
        try:
            with urllib.request.urlopen(req, timeout=130) as r:
                raw = json.loads(r.read())
            n = len(raw.get("elements", []))
            print(f"[OSM] {n} elementos recebidos.")
            os.makedirs("build", exist_ok=True)
            with open(CACHE_RUAS, "w") as f:
                json.dump(raw, f, separators=(",", ":"))
            return raw
        except Exception as e:
            print(f"  Tentativa {tentativa+1}/3 falhou: {e}")
            time.sleep(5)
    print("[ERRO] Não foi possível baixar.")
    sys.exit(1)


def converter(raw, m):
    ruas    = []
    predios = []

    for el in raw.get("elements", []):
        if el.get("type") != "way":
            continue
        geom = el.get("geometry", [])
        if len(geom) < 2:
            continue
        tags = el.get("tags", {})

        if "highway" in tags:
            hw  = tags["highway"]
            pts = [[p["lon"], p["lat"]] for p in geom]
            # filtra pontos fora do bbox
            pts = [p for p in pts
                   if m["lon_min"] <= p[0] <= m["lon_max"]
                   and m["lat_min"] <= p[1] <= m["lat_max"]]
            if len(pts) < 2:
                continue
            pontos = [lonlat_para_px(p[0], p[1], m) for p in pts]
            larg   = LARGURA_PAD.get(hw, LARGURA_DEFAULT)
            if tags.get("lanes"):
                try:
                    larg = max(larg, int(tags["lanes"]) * 3)
                except ValueError:
                    pass
            ow_tag = tags.get("oneway", "no")
            if ow_tag in ("-1", "reverse"):
                pontos = pontos[::-1]   # inverte para manter sentido correto
                oneway = True
            else:
                oneway = ow_tag in ("yes", "1", "true")
            nome   = tags.get("name", "")
            ruas.append({"pontos": pontos, "largura": larg, "oneway": oneway, "nome": nome, "tipo": hw})

        elif "building" in tags:
            coords = [[p["lon"], p["lat"]] for p in geom]
            if coords[0] == coords[-1]:
                coords = coords[:-1]
            if len(coords) < 3:
                continue
            pontos = [lonlat_para_px(c[0], c[1], m) for c in coords]
            predios.append({"pontos": pontos})

    return ruas, predios


def main():
    m = carregar_meta()
    print(f"[META] bbox lat [{m['lat_min']}, {m['lat_max']}]  "
          f"lon [{m['lon_min']}, {m['lon_max']}]")
    print(f"       mapa: {m['larg']} x {m['alt']} px")

    usar_cache = os.path.exists(CACHE_RUAS) and "--local" in sys.argv
    if usar_cache:
        print(f"[OSM] Usando cache: {CACHE_RUAS}")
        with open(CACHE_RUAS) as f:
            raw = json.load(f)
    else:
        raw = baixar_overpass(m)

    ruas, predios = converter(raw, m)
    print(f"[OK] {len(ruas)} ruas  {len(predios)} prédios (colisão)")

    saida = {
        "ruas":    ruas,
        "predios": predios,
        "largura": m["larg"],
        "altura":  m["alt"],
        "bbox":    [m["lat_min"], m["lon_min"], m["lat_max"], m["lon_max"]],
    }
    os.makedirs("maps", exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(saida, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[OK] Salvo: {OUTPUT}")


if __name__ == "__main__":
    main()
