"""
Converte dados geográficos de Santos para coordenadas de jogo (gta_santos).

Sistema de referência (meta.json, zoom=18):
  bbox: lat [-23.987507, -23.931034], lon [-46.340332, -46.292267]
  mapa: 8960 x 11520 px (pré-escala)
  escala Godot: 15 px/m

Fórmula (mesmo que satelite_stream.gd / _geo_para_game):
  x = (lon - min_lon) / (max_lon - min_lon) * largura_px
  y = (1 - (lat - min_lat) / (max_lat - min_lat)) * altura_px
"""

import json, os, math

META = {
    "min_lat": -23.987507, "max_lat": -23.931034,
    "min_lon": -46.340332, "max_lon": -46.292267,
    "larg_px": 8960,       "alt_px":  11520,
}

HERE = os.path.dirname(os.path.abspath(__file__))


def geo_para_game(lat, lon):
    x = (lon - META["min_lon"]) / (META["max_lon"] - META["min_lon"]) * META["larg_px"]
    y = (1.0 - (lat - META["min_lat"]) / (META["max_lat"] - META["min_lat"])) * META["alt_px"]
    return round(x, 2), round(y, 2)


def dentro_do_mapa(lat, lon):
    return (META["min_lat"] <= lat <= META["max_lat"] and
            META["min_lon"] <= lon <= META["max_lon"])


# ── 1. Bairros (cartografia social) ──────────────────────────────────────────

def converter_bairros():
    src = "/home/hericmr/Documentos/projetos/cartografiasocial/public/bairros.geojson"
    with open(src) as f:
        geojson = json.load(f)

    bairros = []
    for feat in geojson["features"]:
        nome = feat["properties"].get("NOME", "")
        geom = feat["geometry"]
        polys_px = []

        rings = []
        if geom["type"] == "Polygon":
            rings = [geom["coordinates"][0]]
        elif geom["type"] == "MultiPolygon":
            for poly in geom["coordinates"]:
                rings.append(poly[0])

        for ring in rings:
            pts = []
            for lon, lat in ring:
                x, y = geo_para_game(lat, lon)
                pts.append([x, y])
            polys_px.append(pts)

        bairros.append({"nome": nome, "poligonos_px": polys_px})

    out = os.path.join(HERE, "bairros.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"bairros": bairros}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[bairros] {len(bairros)} bairros → {out}")


# ── 2. Lugares famosos (Geosantos) ───────────────────────────────────────────

def converter_lugares():
    src = "/home/hericmr/Documentos/projetos/Geosantos/src/data/famous_places.json"
    with open(src) as f:
        lugares = json.load(f)

    out_lugares = []
    ignorados = 0
    for lugar in lugares:
        lat = float(lugar.get("latitude") or 0)
        lon = float(lugar.get("longitude") or 0)
        if lat == 0 and lon == 0:
            ignorados += 1
            continue
        if not dentro_do_mapa(lat, lon):
            ignorados += 1
            continue
        x, y = geo_para_game(lat, lon)
        out_lugares.append({
            "id":          lugar.get("id", ""),
            "nome":        lugar.get("name", ""),
            "descricao":   lugar.get("description", ""),
            "categoria":   lugar.get("category", ""),
            "endereco":    lugar.get("address", ""),
            "imagem":      lugar.get("imageUrl", ""),
            "x": x, "y": y,
        })

    out = os.path.join(HERE, "lugares_famosos.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"lugares": out_lugares}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[lugares] {len(out_lugares)} dentro do mapa, {ignorados} ignorados → {out}")


# ── 3. Linhas de ônibus (wheresheric) ────────────────────────────────────────

def converter_linhas():
    src = "/home/hericmr/Documentos/projetos/wheresheric/public/todas_as_linhas.json"
    with open(src) as f:
        dados = json.load(f)

    linhas_out = []
    for linha in dados["linhas"]:
        percurso_ida_px = []
        for pt in linha.get("percurso_ida", []):
            lat, lon = pt["lat"], pt["lng"]
            if dentro_do_mapa(lat, lon):
                x, y = geo_para_game(lat, lon)
                percurso_ida_px.append([x, y])

        percurso_volta_px = []
        for pt in linha.get("percurso_volta", []):
            lat, lon = pt["lat"], pt["lng"]
            if dentro_do_mapa(lat, lon):
                x, y = geo_para_game(lat, lon)
                percurso_volta_px.append([x, y])

        paradas_px = []
        for parada in linha.get("paradas", []):
            lat, lon = parada["lat"], parada["lng"]
            if dentro_do_mapa(lat, lon):
                x, y = geo_para_game(lat, lon)
                paradas_px.append({
                    "nome":  parada.get("nome", ""),
                    "ordem": parada.get("ordem", 0),
                    "x": x, "y": y,
                })

        linhas_out.append({
            "nome":               linha["nome"],
            "linha_id":           linha["linha_id"],
            "descricao":          linha.get("descricao", ""),
            "percurso_ida_px":    percurso_ida_px,
            "percurso_volta_px":  percurso_volta_px,
            "paradas_px":         paradas_px,
        })

    out = os.path.join(HERE, "linhas_onibus.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"linhas": linhas_out}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[ônibus] {len(linhas_out)} linhas → {out}")


if __name__ == "__main__":
    converter_bairros()
    converter_lugares()
    converter_linhas()
    print("Conversão concluída.")
