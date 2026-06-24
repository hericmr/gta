#!/usr/bin/env python3
"""
baixar_predios_osm.py — Baixa prédios do OpenStreetMap via Overpass API
e gera maps/santos_predios_godot.json diretamente.

Vantagem sobre Google Open Buildings V3:
  - Polígonos na posição correta (sem deslocamento)
  - Tem atributos de altura: height, building:levels
  - Grátis, sem autenticação

Uso:
  python3 baixar_predios_osm.py           # baixa e converte
  python3 baixar_predios_osm.py --local   # usa cache build/buildings_osm_raw.json
"""

import json
import math
import os
import sys
import time

import requests

# ── Constantes de mapa ────────────────────────────────────────────────────────
LAT_MIN = -23.987507;  LAT_MAX = -23.931034
LON_MIN = -46.340332;  LON_MAX = -46.292267
LARG_PX = 8960.0;      ALT_PX  = 11520.0

AREA_MIN_M2  = 30     # filtra construções muito pequenas
ALTURA_PAD   = 8.0    # altura padrão quando não há tag de altura (m)
METROS_ANDAR = 3.0    # altura estimada por andar (building:levels)

OUTPUT_JSON  = "maps/santos_predios_godot.json"
CACHE_RAW    = "build/buildings_osm_raw.json"

# ── Conversão de coordenadas ──────────────────────────────────────────────────

def lonlat_para_pre_escala(lon: float, lat: float) -> list:
    """Converte lon/lat → coordenadas pré-ESCALA (poly_px no JSON do Godot)."""
    x = (lon - LON_MIN) / (LON_MAX - LON_MIN) * LARG_PX
    y = (1.0 - (lat - LAT_MIN) / (LAT_MAX - LAT_MIN)) * ALT_PX
    return [round(x, 3), round(y, 3)]


def area_m2_lonlat(coords: list) -> float:
    """Área aproximada do polígono em m² (projeção cilíndrica equidistante)."""
    lat_c = sum(c[1] for c in coords) / len(coords)
    m_por_lon = math.cos(math.radians(lat_c)) * 111320.0
    m_por_lat = 111320.0
    area = 0.0
    n = len(coords)
    for i in range(n):
        x0, y0 = coords[i][0] * m_por_lon, coords[i][1] * m_por_lat
        x1, y1 = coords[(i + 1) % n][0] * m_por_lon, coords[(i + 1) % n][1] * m_por_lat
        area += x0 * y1 - x1 * y0
    return abs(area) / 2.0


def extrair_altura(tags: dict) -> float:
    """Extrai altura em metros dos tags OSM."""
    if "height" in tags:
        try:
            return float(str(tags["height"]).replace("m", "").replace(",", ".").strip())
        except ValueError:
            pass
    if "building:levels" in tags:
        try:
            return float(tags["building:levels"]) * METROS_ANDAR
        except ValueError:
            pass
    if "building:height" in tags:
        try:
            return float(str(tags["building:height"]).replace("m", "").strip())
        except ValueError:
            pass
    return ALTURA_PAD


# ── Download Overpass ─────────────────────────────────────────────────────────

def baixar_overpass() -> dict:
    query = (
        f"[out:json][timeout:180];"
        f"(way[\"building\"]({LAT_MIN},{LON_MIN},{LAT_MAX},{LON_MAX}););"
        f"out geom tags;"
    )
    print("[OSM] Baixando prédios do Overpass API...")
    print(f"      bbox: {LAT_MIN} {LON_MIN} → {LAT_MAX} {LON_MAX}")

    for tentativa in range(3):
        try:
            r = requests.post(
                "https://overpass-api.de/api/interpreter",
                data=query,
                headers={"User-Agent": "GTA-Santos-Game/1.0"},
                timeout=200,
            )
            if r.status_code == 200:
                dados = r.json()
                n = len(dados.get("elements", []))
                print(f"[OSM] {n} elementos recebidos.")
                os.makedirs("build", exist_ok=True)
                with open(CACHE_RAW, "w", encoding="utf-8") as f:
                    json.dump(dados, f, separators=(",", ":"))
                return dados
            else:
                print(f"[AVISO] HTTP {r.status_code} — tentativa {tentativa+1}/3")
        except Exception as e:
            print(f"[AVISO] {e} — tentativa {tentativa+1}/3")
        time.sleep(5)

    print("[ERRO] Não foi possível baixar do Overpass.")
    sys.exit(1)


# ── Conversão ─────────────────────────────────────────────────────────────────

def converter(dados: dict) -> list:
    predios = []
    ignorados = {"sem_geom": 0, "fora_bbox": 0, "area_pequena": 0}

    for el in dados.get("elements", []):
        if el.get("type") != "way":
            continue
        geom = el.get("geometry", [])
        if len(geom) < 3:
            ignorados["sem_geom"] += 1
            continue

        # Fecha o anel se necessário
        coords_ll = [[p["lon"], p["lat"]] for p in geom]
        if coords_ll[0] != coords_ll[-1]:
            coords_ll.append(coords_ll[0])

        # Filtro bbox
        lons = [c[0] for c in coords_ll]
        lats = [c[1] for c in coords_ll]
        if (min(lons) < LON_MIN or max(lons) > LON_MAX or
                min(lats) < LAT_MIN or max(lats) > LAT_MAX):
            ignorados["fora_bbox"] += 1
            continue

        area = area_m2_lonlat(coords_ll)
        if area < AREA_MIN_M2:
            ignorados["area_pequena"] += 1
            continue

        tags     = el.get("tags", {})
        altura_m = extrair_altura(tags)
        # coords_ll tem o ponto de fechamento repetido (GeoJSON ring); remove-o para Godot
        coords_open = coords_ll[:-1]
        poly_px  = [lonlat_para_pre_escala(lon, lat) for lon, lat in coords_open]

        predios.append({
            "osm_id":   el["id"],
            "poly_px":  poly_px,
            "altura_m": round(altura_m, 1),
            "area_m2":  round(area, 1),
        })

    print(f"[OSM] Convertidos: {len(predios)} prédios")
    print(f"      Ignorados: sem_geom={ignorados['sem_geom']}, "
          f"fora_bbox={ignorados['fora_bbox']}, area<{AREA_MIN_M2}m²={ignorados['area_pequena']}")

    # Estatísticas de altura
    com_altura = sum(1 for p in predios
                     if p["altura_m"] != ALTURA_PAD)
    print(f"      Com altura OSM: {com_altura} ({100*com_altura//max(len(predios),1)}%)")
    print(f"      Usando padrão {ALTURA_PAD}m: {len(predios)-com_altura}")

    return predios


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    usar_local = "--local" in sys.argv

    if usar_local and os.path.exists(CACHE_RAW):
        print(f"[OSM] Usando cache: {CACHE_RAW}")
        with open(CACHE_RAW, encoding="utf-8") as f:
            dados = json.load(f)
    else:
        dados = baixar_overpass()

    predios = converter(dados)

    os.makedirs("maps", exist_ok=True)
    saida = {"predios": predios}
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, separators=(",", ":"))

    tamanho_mb = os.path.getsize(OUTPUT_JSON) / 1_048_576
    print(f"\n[OSM] Salvo: {OUTPUT_JSON}  ({tamanho_mb:.1f} MB)")
    print(f"      {len(predios)} prédios prontos para o Godot")
    print(f"\n  Rode o jogo no Godot para ver os novos prédios.")


if __name__ == "__main__":
    main()
