#!/usr/bin/env python3
"""
converter_mapa_osm.py — Converte mapa.osm → santos_predios_godot.json
e faz merge com o JSON atual: OSM substitui prédios na sua área de cobertura,
o resto do JSON atual é preservado.

Uso:
  python3 converter_mapa_osm.py
"""

import json
import math
import os
import xml.etree.ElementTree as ET

OSM_FILE   = "mapa.osm"
META_FILE  = "assets/tiles/meta.json"
JSON_ATUAL = "maps/santos_predios_godot.json"
OUTPUT     = "maps/santos_predios_godot.json"
BACKUP     = "maps/santos_predios_godot.backup.json"

AREA_MIN_M2  = 30
ALTURA_PAD   = 8.0
METROS_ANDAR = 3.0


def carregar_meta():
    with open(META_FILE) as f:
        m = json.load(f)
    bbox = m["bbox"]
    return {
        "lat_min": bbox[0], "lon_min": bbox[1],
        "lat_max": bbox[2], "lon_max": bbox[3],
        "larg":    float(m["largura_map_px"]),
        "alt":     float(m["altura_map_px"]),
    }


def lonlat_para_px(lon, lat, m):
    x = (lon - m["lon_min"]) / (m["lon_max"] - m["lon_min"]) * m["larg"]
    y = (1.0 - (lat - m["lat_min"]) / (m["lat_max"] - m["lat_min"])) * m["alt"]
    return [round(x, 3), round(y, 3)]


def area_m2(coords):
    lat_c = sum(c[1] for c in coords) / len(coords)
    m_lon = math.cos(math.radians(lat_c)) * 111320.0
    m_lat = 111320.0
    a = 0.0
    n = len(coords)
    for i in range(n):
        x0, y0 = coords[i][0] * m_lon, coords[i][1] * m_lat
        x1, y1 = coords[(i + 1) % n][0] * m_lon, coords[(i + 1) % n][1] * m_lat
        a += x0 * y1 - x1 * y0
    return abs(a) / 2.0


def extrair_altura(tags):
    for key in ("height", "building:height"):
        if key in tags:
            try:
                return float(str(tags[key]).replace("m", "").replace(",", ".").strip())
            except ValueError:
                pass
    if "building:levels" in tags:
        try:
            return float(tags["building:levels"]) * METROS_ANDAR
        except ValueError:
            pass
    return ALTURA_PAD


def px_para_latlon(px, m):
    """Converte [x_px, y_px] → (lat, lon) — para classificar prédios do JSON atual."""
    x, y = px[0], px[1]
    lon = x / m["larg"] * (m["lon_max"] - m["lon_min"]) + m["lon_min"]
    lat = (1.0 - y / m["alt"]) * (m["lat_max"] - m["lat_min"]) + m["lat_min"]
    return lat, lon


def classificar_tipo(tags: dict) -> str:
    bt = tags.get("building", "yes").lower()
    if bt in ("apartments", "residential", "dormitory", "bungalow", "detached",
              "semidetached_house", "terrace", "house"):
        return "residencial"
    if bt in ("commercial", "retail", "supermarket", "hotel", "mall", "office"):
        return "comercial"
    if bt in ("industrial", "warehouse", "storage_tank", "manufacture"):
        return "industrial"
    if bt in ("school", "university", "college", "kindergarten", "church",
              "cathedral", "chapel", "hospital", "public", "civic", "government"):
        return "publico"
    if bt in ("garage", "garages", "parking", "carport"):
        return "garagem"
    return "geral"


def montar_aneis_building(segmentos):
    """Monta anéis de building relations da mesma forma que features."""
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


def main():
    m = carregar_meta()

    # ── Parsear mapa.osm ──────────────────────────────────────────────────────
    print(f"[OSM] Lendo {OSM_FILE}...")
    tree = ET.parse(OSM_FILE)
    root = tree.getroot()

    # Coleta todos os nós (id → lat/lon)
    nodes = {}
    for n in root.findall("node"):
        nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))

    # Bounds do OSM (para saber que área ele cobre)
    bounds_el = root.find("bounds")
    osm_bounds = {
        "lat_min": float(bounds_el.get("minlat")),
        "lat_max": float(bounds_el.get("maxlat")),
        "lon_min": float(bounds_el.get("minlon")),
        "lon_max": float(bounds_el.get("maxlon")),
    }
    print(f"[OSM] Bounds: lat [{osm_bounds['lat_min']} → {osm_bounds['lat_max']}]  "
          f"lon [{osm_bounds['lon_min']} → {osm_bounds['lon_max']}]")

    # Converte prédios do OSM
    predios_osm = []
    ignorados = {"sem_nos": 0, "fora_meta": 0, "area_pequena": 0, "sem_geom": 0}

    for w in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in w.findall("tag")}
        if "building" not in tags:
            continue

        refs = [nd.get("ref") for nd in w.findall("nd")]
        if len(refs) < 4:
            ignorados["sem_nos"] += 1
            continue

        # Resolve referências para coordenadas
        coords = []
        ok = True
        for ref in refs:
            if ref not in nodes:
                ok = False
                break
            lat, lon = nodes[ref]
            coords.append((lon, lat))
        if not ok:
            ignorados["sem_geom"] += 1
            continue

        # Remove ponto de fechamento repetido
        if coords[0] == coords[-1]:
            coords = coords[:-1]
        if len(coords) < 3:
            ignorados["sem_nos"] += 1
            continue

        # Filtra pelo bbox do meta.json (sem satélite não há contexto)
        lons = [c[0] for c in coords]
        lats = [c[1] for c in coords]
        if (min(lons) < m["lon_min"] or max(lons) > m["lon_max"] or
                min(lats) < m["lat_min"] or max(lats) > m["lat_max"]):
            ignorados["fora_meta"] += 1
            continue

        a = area_m2(coords)
        if a < AREA_MIN_M2:
            ignorados["area_pequena"] += 1
            continue

        altura = extrair_altura(tags)
        poly   = [lonlat_para_px(lon, lat, m) for lon, lat in coords]
        tipo   = classificar_tipo(tags)

        predios_osm.append({
            "osm_id":   int(w.get("id")),
            "poly_px":  poly,
            "altura_m": round(altura, 1),
            "area_m2":  round(a, 1),
            "tipo":     tipo,
        })

    print(f"[OSM] {len(predios_osm)} prédios (ways) convertidos  |  "
          f"ignorados: {ignorados}")

    # ── Relations multipolígono de buildings ──────────────────────────────────
    rel_adicionados = 0
    ids_osm_ways = {p["osm_id"] for p in predios_osm}
    for rel in root.findall("relation"):
        tags = {t.get("k"): t.get("v") for t in rel.findall("tag")}
        if "building" not in tags or tags.get("type") != "multipolygon":
            continue

        segs = []
        for member in rel.findall("member"):
            if member.get("type") != "way" or member.get("role") not in ("outer", ""):
                continue
            ref = member.get("ref")
            nd_refs = [nd.get("ref") for nd in root.findall(f"way[@id='{ref}']/nd")]
            if not nd_refs:
                continue
            coords_seg = []
            for r in nd_refs:
                if r in nodes:
                    lat, lon = nodes[r]
                    coords_seg.append((lon, lat))
            if len(coords_seg) >= 2:
                segs.append(coords_seg)

        for anel in montar_aneis_building(segs):
            lons = [c[0] for c in anel]
            lats = [c[1] for c in anel]
            if (min(lons) < m["lon_min"] or max(lons) > m["lon_max"] or
                    min(lats) < m["lat_min"] or max(lats) > m["lat_max"]):
                continue
            a = area_m2(anel)
            if a < AREA_MIN_M2:
                continue
            poly   = [lonlat_para_px(lon, lat, m) for lon, lat in anel]
            tipo   = classificar_tipo(tags)
            altura = extrair_altura(tags)
            predios_osm.append({
                "osm_id":   int(rel.get("id")),
                "poly_px":  poly,
                "altura_m": round(altura, 1),
                "area_m2":  round(a, 1),
                "tipo":     tipo,
            })
            rel_adicionados += 1

    print(f"[OSM] +{rel_adicionados} prédios de relations multipolígono")

    # ── Merge com JSON atual ──────────────────────────────────────────────────
    predios_finais = list(predios_osm)
    ids_osm = {p["osm_id"] for p in predios_osm}

    if os.path.exists(JSON_ATUAL):
        with open(JSON_ATUAL) as f:
            atual = json.load(f)

        mantidos = descartados = 0
        for p in atual.get("predios", []):
            osm_id = p.get("osm_id")

            # Já existe no novo OSM → descarta a versão antiga
            if osm_id in ids_osm:
                descartados += 1
                continue

            # Fora da área de cobertura do mapa.osm → mantém
            if p.get("poly_px"):
                lat, lon = px_para_latlon(p["poly_px"][0], m)
                fora = (lat < osm_bounds["lat_min"] or lat > osm_bounds["lat_max"] or
                        lon < osm_bounds["lon_min"] or lon > osm_bounds["lon_max"])
                if fora:
                    predios_finais.append(p)
                    mantidos += 1
                else:
                    # Dentro da área do OSM mas não encontrado nele → OSM removeu ou renumerou
                    descartados += 1

        print(f"[Merge] Mantidos do JSON atual (fora da área OSM): {mantidos}")
        print(f"[Merge] Descartados (substituídos ou removidos): {descartados}")

        # Backup antes de sobrescrever
        import shutil
        shutil.copy(JSON_ATUAL, BACKUP)
        print(f"[Backup] {BACKUP}")
    else:
        print("[Aviso] JSON atual não encontrado, gerando do zero.")

    # ── Salvar ────────────────────────────────────────────────────────────────
    os.makedirs("maps", exist_ok=True)
    saida = {"predios": predios_finais}
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, separators=(",", ":"))

    tamanho_kb = os.path.getsize(OUTPUT) / 1024
    com_h = sum(1 for p in predios_finais if p["altura_m"] != ALTURA_PAD)
    print(f"\n[OK] {OUTPUT}  ({tamanho_kb:.0f} KB)")
    print(f"     {len(predios_finais)} prédios totais")
    print(f"     Com altura real: {com_h} ({100*com_h//max(len(predios_finais),1)}%)")
    print(f"     Usando padrão {ALTURA_PAD}m: {len(predios_finais)-com_h}")


if __name__ == "__main__":
    main()
