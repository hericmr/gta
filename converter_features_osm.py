#!/usr/bin/env python3
"""
converter_features_osm.py — Extrai features geográficas do mapa.osm
(canais, parques, água, porto) e gera maps/santos_features.json.

Uso:
  python3 converter_features_osm.py
"""
import json, math, os, xml.etree.ElementTree as ET

OSM_FILE  = "mapa.osm"
META_FILE = "assets/tiles/meta.json"
OUTPUT    = "maps/santos_features.json"

CANAL_LARGURA_PX = 15.0   # largura visual dos canais (pre-ESCALA units)
AREA_MIN_M2      = 50     # ignora polígonos menores que isso


def carregar_meta():
    with open(META_FILE) as f:
        m = json.load(f)
    bbox = m["bbox"]
    return {
        "lat_min": bbox[0], "lon_min": bbox[1],
        "lat_max": bbox[2], "lon_max": bbox[3],
        "larg": float(m["largura_map_px"]),
        "alt":  float(m["altura_map_px"]),
    }


def to_px(lon, lat, m):
    x = (lon - m["lon_min"]) / (m["lon_max"] - m["lon_min"]) * m["larg"]
    y = (1.0 - (lat - m["lat_min"]) / (m["lat_max"] - m["lat_min"])) * m["alt"]
    return [round(x, 1), round(y, 1)]


def area_m2(coords_lonlat):
    if len(coords_lonlat) < 3:
        return 0
    lat_c = sum(c[1] for c in coords_lonlat) / len(coords_lonlat)
    m_lon = math.cos(math.radians(lat_c)) * 111320.0
    m_lat = 111320.0
    a = 0.0
    n = len(coords_lonlat)
    for i in range(n):
        x0 = coords_lonlat[i][0] * m_lon
        y0 = coords_lonlat[i][1] * m_lat
        x1 = coords_lonlat[(i + 1) % n][0] * m_lon
        y1 = coords_lonlat[(i + 1) % n][1] * m_lat
        a += x0 * y1 - x1 * y0
    return abs(a) / 2.0


def dentro_meta(coords_lonlat, m):
    lons = [c[0] for c in coords_lonlat]
    lats = [c[1] for c in coords_lonlat]
    return (min(lons) >= m["lon_min"] and max(lons) <= m["lon_max"] and
            min(lats) >= m["lat_min"] and max(lats) <= m["lat_max"])


def main():
    m = carregar_meta()
    print(f"[Meta] bbox lat [{m['lat_min']} → {m['lat_max']}]  "
          f"lon [{m['lon_min']} → {m['lon_max']}]")

    print(f"[OSM] Lendo {OSM_FILE}...")
    tree = ET.parse(OSM_FILE)
    root = tree.getroot()

    nodes = {}
    for n in root.findall("node"):
        nodes[n.get("id")] = (float(n.get("lon")), float(n.get("lat")))

    canais  = []
    verde   = []
    agua    = []
    porto   = []
    ign     = {"fora": 0, "pequeno": 0, "sem_nos": 0}

    for w in root.findall("way"):
        tags  = {t.get("k"): t.get("v") for t in w.findall("tag")}
        refs  = [nd.get("ref") for nd in w.findall("nd")]
        coords = [nodes[r] for r in refs if r in nodes]  # (lon, lat)

        if len(coords) < 2:
            ign["sem_nos"] += 1
            continue

        # ── Canais abertos (linhas, não polígonos) ───────────────────────────
        if tags.get("waterway") == "canal" and tags.get("tunnel") != "culvert":
            # Filtra pontos dentro do meta
            pts_dentro = [c for c in coords
                          if m["lon_min"] <= c[0] <= m["lon_max"]
                          and m["lat_min"] <= c[1] <= m["lat_max"]]
            if len(pts_dentro) < 2:
                ign["fora"] += 1
                continue
            canais.append({
                "pontos":  [to_px(c[0], c[1], m) for c in pts_dentro],
                "largura": CANAL_LARGURA_PX,
                "nome":    tags.get("name", ""),
            })
            continue

        # Para polígonos: exige pelo menos 3 pontos e fechamento
        if len(coords) < 3:
            continue

        # Fecha o anel se necessário
        if coords[0] != coords[-1]:
            coords.append(coords[0])
        poly_ll = coords[:-1]  # sem o ponto de fechamento repetido

        if not dentro_meta(poly_ll, m):
            ign["fora"] += 1
            continue

        a = area_m2(poly_ll)
        if a < AREA_MIN_M2:
            ign["pequeno"] += 1
            continue

        poly_px = [to_px(c[0], c[1], m) for c in poly_ll]
        nome    = tags.get("name", "")

        # ── Parques, jardins, áreas verdes ───────────────────────────────────
        is_verde = (
            tags.get("leisure") in ("park", "garden") or
            tags.get("landuse") in ("grass", "greenfield", "recreation_ground",
                                    "meadow", "village_green") or
            tags.get("natural") in ("grassland", "wetland", "scrub") or
            tags.get("tourism") == "zoo"
        )
        if is_verde:
            verde.append({"poly_px": poly_px, "nome": nome, "area_m2": round(a, 1)})
            continue

        # ── Corpos d'água (polígonos fechados) ───────────────────────────────
        is_agua = (
            tags.get("natural") == "water" or
            tags.get("waterway") in ("riverbank", "dock", "basin")
        )
        if is_agua:
            agua.append({"poly_px": poly_px, "nome": nome})
            continue

        # ── Porto e industrial ────────────────────────────────────────────────
        is_porto = (
            tags.get("landuse") in ("harbour", "port", "industrial") or
            tags.get("man_made") in ("pier", "quay")
        )
        if is_porto:
            porto.append({"poly_px": poly_px, "nome": nome})
            continue

    print(f"[OK] Canais abertos:  {len(canais)}")
    print(f"     Parques/verde:   {len(verde)}")
    print(f"     Água (polígono): {len(agua)}")
    print(f"     Porto/industrial:{len(porto)}")
    print(f"     Ignorados:       fora={ign['fora']}  pequeno={ign['pequeno']}  sem_nós={ign['sem_nos']}")

    os.makedirs("maps", exist_ok=True)
    saida = {
        "canais": canais,
        "verde":  verde,
        "agua":   agua,
        "porto":  porto,
    }
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, separators=(",", ":"))

    kb = os.path.getsize(OUTPUT) / 1024
    print(f"\n[Salvo] {OUTPUT}  ({kb:.0f} KB)")


if __name__ == "__main__":
    main()
