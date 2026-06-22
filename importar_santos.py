#!/usr/bin/env python3
"""
importar_santos.py — Baixa dados de Santos via OpenStreetMap e gera maps/santos.json
para ser carregado pelo Godot 3.

Uso:
    python3 importar_santos.py

Requer apenas a biblioteca padrão do Python 3.
"""

import json
import math
import sys
import urllib.request
import urllib.error
import urllib.parse
import os

# ------------------------------------------------------------
# Área de Santos — ajuste as bordas se quiser cobrir mais
# (min_lat, min_lon, max_lat, max_lon)
# ------------------------------------------------------------
BBOX = (-23.975, -46.380, -23.905, -46.285)

# Largura do mapa em pixels (altura é calculada com proporção correta)
LARGURA_PX = 8000

# Tipos de estrada que viram colisão (remove rotas de pedestres/bicicleta)
HIGHWAYS_IGNORADOS = {
    "footway", "path", "steps", "cycleway",
    "pedestrian", "track", "construction"
}

# Largura visual de cada tipo de via (em pixels no mapa final)
LARGURA_POR_TIPO = {
    "motorway": 22, "motorway_link": 16,
    "trunk": 20,    "trunk_link": 14,
    "primary": 16,  "primary_link": 12,
    "secondary": 13, "secondary_link": 10,
    "tertiary": 10,  "tertiary_link": 8,
    "residential": 8,
    "unclassified": 8,
    "living_street": 6,
    "service": 5,
}

# ------------------------------------------------------------

def calcular_dimensoes(bbox: tuple) -> tuple[int, int]:
    min_lat, min_lon, max_lat, max_lon = bbox
    lat_medio = math.radians((min_lat + max_lat) / 2)
    # Longitude precisa de correção pelo cosseno da latitude
    razao = (max_lon - min_lon) * math.cos(lat_medio) / (max_lat - min_lat)
    altura = int(LARGURA_PX / razao)
    return LARGURA_PX, altura


def geo_para_pixel(lat: float, lon: float,
                   bbox: tuple, largura: int, altura: int) -> tuple[float, float]:
    min_lat, min_lon, max_lat, max_lon = bbox
    x = (lon - min_lon) / (max_lon - min_lon) * largura
    # Y invertido: norte (lat maior) = topo da tela (Y menor)
    y = (1.0 - (lat - min_lat) / (max_lat - min_lat)) * altura
    return round(x, 1), round(y, 1)


def baixar_osm(bbox: tuple) -> dict:
    min_lat, min_lon, max_lat, max_lon = bbox
    # bbox no Overpass usa parênteses: (sul,oeste,norte,leste)
    query = f"""[out:json][timeout:90];
(
  way["highway"]({min_lat},{min_lon},{max_lat},{max_lon});
  way["building"]({min_lat},{min_lon},{max_lat},{max_lon});
);
out geom;"""

    url = "https://overpass-api.de/api/interpreter"
    payload = urllib.parse.urlencode({"data": query}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "santos-driver-godot/1.0"
        }
    )
    print("  Conectando ao Overpass API...")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            conteudo = resp.read()
    except urllib.error.URLError as e:
        print(f"  Erro de rede: {e}")
        sys.exit(1)

    # Cache do OSM bruto para reuso
    with open("maps/santos_osm_raw.json", "wb") as f:
        f.write(conteudo)
    print("  Cache bruto salvo em maps/santos_osm_raw.json")

    return json.loads(conteudo)


def processar(dados: dict, bbox: tuple, largura: int, altura: int) -> dict:
    ruas = []
    predios = []
    ignorados = 0

    for el in dados.get("elements", []):
        if el.get("type") != "way":
            continue

        tags = el.get("tags", {})
        geometria = el.get("geometry", [])

        if len(geometria) < 2:
            continue

        # Converte todos os nós para pixels
        pontos = [geo_para_pixel(n["lat"], n["lon"], bbox, largura, altura)
                  for n in geometria]

        if "highway" in tags:
            tipo = tags["highway"]
            if tipo in HIGHWAYS_IGNORADOS:
                ignorados += 1
                continue
            largura_via = LARGURA_POR_TIPO.get(tipo, 8)
            nome = tags.get("name", "")
            ruas.append({"pontos": pontos, "largura": largura_via,
                         "tipo": tipo, "nome": nome})

        elif "building" in tags:
            if len(pontos) < 3:
                continue
            # OSM fecha o polígono repetindo o 1º ponto — remove o último
            if pontos[0] == pontos[-1]:
                pontos = pontos[:-1]
            if len(pontos) >= 3:
                predios.append({"pontos": pontos})

    if ignorados:
        print(f"  {ignorados} vias de pedestres/bicicleta ignoradas")

    return {
        "ruas": ruas,
        "predios": predios,
        "largura": largura,
        "altura": altura,
        "bbox": list(bbox)
    }


def main():
    os.makedirs("maps", exist_ok=True)

    # Reutiliza cache se já existe
    cache = "maps/santos_osm_raw.json"
    if os.path.exists(cache):
        resp = input(f"Cache '{cache}' encontrado. Reutilizar? [S/n] ").strip().lower()
        if resp in ("", "s", "y"):
            print("  Carregando cache...")
            with open(cache, encoding="utf-8") as f:
                dados = json.load(f)
        else:
            print("Baixando dados frescos de Santos...")
            dados = baixar_osm(BBOX)
    else:
        print("Baixando dados de Santos via Overpass API (pode demorar ~30s)...")
        dados = baixar_osm(BBOX)

    total = len(dados.get("elements", []))
    print(f"  {total} elementos OSM recebidos")

    largura, altura = calcular_dimensoes(BBOX)
    print(f"  Mapa: {largura} x {altura} px")

    print("Processando geometria...")
    resultado = processar(dados, BBOX, largura, altura)

    print(f"  Ruas:    {len(resultado['ruas'])}")
    print(f"  Prédios: {len(resultado['predios'])}")

    saida = "maps/santos.json"
    with open(saida, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, separators=(",", ":"))

    tamanho_kb = os.path.getsize(saida) // 1024
    print(f"\nSalvo em {saida} ({tamanho_kb} KB)")
    print("Próximo passo: no Godot, troque World por WorldOSM na cena Main.tscn")


if __name__ == "__main__":
    main()
