#!/usr/bin/env python3
"""
converter_features_osm.py — Extrai features geográficas do mapa.osm
(canais, parques, praias, água, porto, mar) e gera maps/santos_features.json.

Uso:
  python3 converter_features_osm.py
"""
import json, math, os, xml.etree.ElementTree as ET

OSM_FILE  = "mapa.osm"
META_FILE = "assets/tiles/meta.json"
OUTPUT    = "maps/santos_features.json"

CANAL_LARGURA_PX = 15.0
AREA_MIN_M2      = 50


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


def parcialmente_dentro(coords_lonlat, m):
    """True se pelo menos um ponto está dentro do bbox."""
    for c in coords_lonlat:
        if m["lon_min"] <= c[0] <= m["lon_max"] and m["lat_min"] <= c[1] <= m["lat_max"]:
            return True
    return False


def dentro_meta(coords_lonlat, m):
    lons = [c[0] for c in coords_lonlat]
    lats = [c[1] for c in coords_lonlat]
    return (min(lons) >= m["lon_min"] and max(lons) <= m["lon_max"] and
            min(lats) >= m["lat_min"] and max(lats) <= m["lat_max"])


def clipar_ao_bbox(coords, m):
    """Retorna apenas os pontos dentro do bbox (simplificação sem interpolação)."""
    return [c for c in coords
            if m["lon_min"] <= c[0] <= m["lon_max"]
            and m["lat_min"] <= c[1] <= m["lat_max"]]


def montar_aneis(segmentos):
    """
    Recebe lista de segmentos [(lon,lat), ...] e tenta montar anéis fechados
    encadeando extremidades coincidentes. Retorna lista de anéis.
    """
    restantes = [list(s) for s in segmentos if len(s) >= 2]
    aneis = []

    while restantes:
        anel = restantes.pop(0)
        mudou = True
        while mudou:
            mudou = False
            for i, seg in enumerate(restantes):
                if anel[-1] == seg[0]:
                    anel.extend(seg[1:])
                elif anel[-1] == seg[-1]:
                    anel.extend(reversed(seg[:-1]))
                elif anel[0] == seg[-1]:
                    anel = seg[:-1] + anel
                elif anel[0] == seg[0]:
                    anel = list(reversed(seg))[:-1] + anel
                else:
                    continue
                restantes.pop(i)
                mudou = True
                break

        if anel[0] == anel[-1]:
            anel = anel[:-1]
        if len(anel) >= 3:
            aneis.append(anel)

    return aneis


def resolver_relation_outers(relation, nodes_map, ways_refs_map):
    """Resolve os anéis externos de uma relation multipolígono."""
    segs = []
    for member in relation.findall("member"):
        if member.get("type") != "way":
            continue
        role = member.get("role", "")
        if role not in ("outer", ""):
            continue
        ref = member.get("ref")
        if ref not in ways_refs_map:
            continue
        coords = [nodes_map[r] for r in ways_refs_map[ref] if r in nodes_map]
        if len(coords) >= 2:
            segs.append(coords)
    return montar_aneis(segs)


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

    ways_refs = {}
    for w in root.findall("way"):
        ways_refs[w.get("id")] = [nd.get("ref") for nd in w.findall("nd")]

    canais  = []
    verde   = []
    praia   = []
    agua    = []
    porto   = []
    mar     = []
    ign     = {"fora": 0, "pequeno": 0, "sem_nos": 0}

    # ── Coastline → polígono do mar ───────────────────────────────────────────
    coast_segs = []
    for w in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in w.findall("tag")}
        if tags.get("natural") != "coastline":
            continue
        refs   = ways_refs.get(w.get("id"), [])
        coords = [nodes[r] for r in refs if r in nodes]
        dentro = [c for c in coords
                  if m["lon_min"] <= c[0] <= m["lon_max"]
                  and m["lat_min"] <= c[1] <= m["lat_max"]]
        if len(dentro) >= 2:
            coast_segs.append(dentro)

    if coast_segs:
        aneis_coast = montar_aneis(coast_segs)
        if aneis_coast:
            # Usa o anel com mais pontos como linha de costa principal
            costa = sorted(aneis_coast, key=len, reverse=True)[0]
        else:
            # Fallback: concatena todos os segmentos ordenados por longitude
            costa = sorted([c for seg in coast_segs for c in seg], key=lambda c: c[0])

        # Polígono do mar: linha de costa + cantos sul do bbox
        if len(costa) >= 2:
            costa_sorted = sorted(costa, key=lambda c: c[0])  # oeste → leste
            mar_poly = list(costa_sorted)
            mar_poly.append((m["lon_max"], m["lat_min"]))
            mar_poly.append((m["lon_min"], m["lat_min"]))
            mar.append({
                "poly_px": [to_px(c[0], c[1], m) for c in mar_poly],
                "nome": "Oceano Atlântico",
            })
            print(f"[Mar] Polígono criado com {len(mar_poly)} pontos")

    # ── Ways ──────────────────────────────────────────────────────────────────
    def processar_poligono(coords, tags):
        if len(coords) < 3:
            ign["sem_nos"] += 1
            return

        if coords[0] != coords[-1]:
            coords.append(coords[0])
        poly_ll = coords[:-1]

        if not parcialmente_dentro(poly_ll, m):
            ign["fora"] += 1
            return

        a = area_m2(poly_ll)
        if a < AREA_MIN_M2:
            ign["pequeno"] += 1
            return

        # Clip ao bbox (mantém apenas pontos dentro)
        clipped = clipar_ao_bbox(poly_ll, m)
        if len(clipped) < 3:
            ign["fora"] += 1
            return

        poly_px = [to_px(c[0], c[1], m) for c in clipped]
        nome    = tags.get("name", "")

        if tags.get("natural") == "beach":
            praia.append({"poly_px": poly_px, "nome": nome, "area_m2": round(a, 1)})
            return True

        is_verde = (
            tags.get("leisure") in ("park", "garden") or
            tags.get("landuse") in ("grass", "greenfield", "recreation_ground",
                                    "meadow", "village_green") or
            tags.get("natural") in ("grassland", "wetland", "scrub") or
            tags.get("tourism") == "zoo"
        )
        if is_verde:
            verde.append({"poly_px": poly_px, "nome": nome, "area_m2": round(a, 1)})
            return True

        is_agua = (
            tags.get("natural") == "water" or
            tags.get("waterway") in ("riverbank", "dock", "basin")
        )
        if is_agua:
            agua.append({"poly_px": poly_px, "nome": nome})
            return True

        is_porto = (
            tags.get("landuse") in ("harbour", "port", "industrial") or
            tags.get("man_made") in ("pier", "quay")
        )
        if is_porto:
            porto.append({"poly_px": poly_px, "nome": nome})
            return True

    for w in root.findall("way"):
        tags   = {t.get("k"): t.get("v") for t in w.findall("tag")}
        refs   = [nd.get("ref") for nd in w.findall("nd")]
        coords = [nodes[r] for r in refs if r in nodes]

        if len(coords) < 2:
            ign["sem_nos"] += 1
            continue

        # Canais (linhas)
        if tags.get("waterway") == "canal" and tags.get("tunnel") != "culvert":
            pts = clipar_ao_bbox(coords, m)
            if len(pts) >= 2:
                canais.append({
                    "pontos":  [to_px(c[0], c[1], m) for c in pts],
                    "largura": CANAL_LARGURA_PX,
                    "nome":    tags.get("name", ""),
                })
            else:
                ign["fora"] += 1
            continue

        processar_poligono(list(coords), tags)

    # ── Relations (multipolígonos) ────────────────────────────────────────────
    for rel in root.findall("relation"):
        tags = {t.get("k"): t.get("v") for t in rel.findall("tag")}
        if tags.get("type") != "multipolygon":
            continue

        nat = tags.get("natural", "")
        lei = tags.get("leisure", "")
        is_relevante = (
            nat in ("beach", "water") or
            lei in ("park", "garden") or
            tags.get("landuse") in ("harbour", "port", "industrial",
                                    "grass", "greenfield", "recreation_ground")
        )
        if not is_relevante:
            continue

        aneis = resolver_relation_outers(rel, nodes, ways_refs)
        for anel in aneis:
            processar_poligono(anel, tags)

    print(f"[OK] Canais:          {len(canais)}")
    print(f"     Parques/verde:   {len(verde)}")
    print(f"     Praias:          {len(praia)}")
    print(f"     Água (polígono): {len(agua)}")
    print(f"     Porto/industrial:{len(porto)}")
    print(f"     Mar:             {len(mar)}")
    print(f"     Ignorados:       fora={ign['fora']}  pequeno={ign['pequeno']}  sem_nós={ign['sem_nos']}")

    os.makedirs("maps", exist_ok=True)
    saida = {
        "canais": canais,
        "verde":  verde,
        "praia":  praia,
        "agua":   agua,
        "porto":  porto,
        "mar":    mar,
    }
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, separators=(",", ":"))

    kb = os.path.getsize(OUTPUT) / 1024
    print(f"\n[Salvo] {OUTPUT}  ({kb:.0f} KB)")


if __name__ == "__main__":
    main()
