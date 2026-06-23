#!/usr/bin/env python3
"""
fase4_relatorio.py - Fase 4: gera build/RELATORIO_alturas.md
a partir de maps/santos_buildings_2p5d.json.
"""

import json
import math
import os
import sys
from datetime import date

INPUT  = "maps/santos_buildings_2p5d.json"
OUTPUT = "build/RELATORIO_alturas.md"


def stats(valores):
    if not valores:
        return 0, 0.0, 0.0, 0.0
    return (
        len(valores),
        min(valores),
        sum(valores) / len(valores),
        max(valores),
    )


def main():
    if not os.path.exists(INPUT):
        print(f"[ERRO] {INPUT} nao encontrado. Rode fase3_mesclar.py primeiro.")
        sys.exit(1)

    with open(INPUT, encoding="utf-8") as f:
        data = json.load(f)

    predios = data["predios"]
    total   = len(predios)

    alturas = [p["altura_m"] for p in predios]
    areas   = [p["area_m2"]  for p in predios]
    fontes  = {}
    for p in predios:
        fontes[p["altura_fonte"]] = fontes.get(p["altura_fonte"], 0) + 1

    n_alt, mn_alt, med_alt, mx_alt = stats(alturas)
    n_ar,  mn_ar,  med_ar,  mx_ar  = stats(areas)

    # Bbox efetivo
    lons = [xy[0] for p in predios for xy in p["poly_lonlat"]]
    lats = [xy[1] for p in predios for xy in p["poly_lonlat"]]

    tipos = {}
    for p in predios:
        t = p.get("building", "yes")
        tipos[t] = tipos.get(t, 0) + 1
    top_tipos = sorted(tipos.items(), key=lambda x: -x[1])[:10]

    linhas = [
        f"# Relatório de Alturas — Santos/SP",
        f"",
        f"Gerado em: {date.today().isoformat()}",
        f"",
        f"## Resumo",
        f"",
        f"| Métrica | Valor |",
        f"|---|---|",
        f"| Total de prédios | {total} |",
        f"| Fonte principal (2.5D GEE) | {fontes.get('2p5d', 0)} ({100*fontes.get('2p5d',0)/total:.1f}%) |",
        f"| Fallback osm_height | {fontes.get('osm_height', 0)} ({100*fontes.get('osm_height',0)/total:.1f}%) |",
        f"| Fallback building:levels | {fontes.get('levels', 0)} ({100*fontes.get('levels',0)/total:.1f}%) |",
        f"| Fallback default por tipo | {fontes.get('default', 0)} ({100*fontes.get('default',0)/total:.1f}%) |",
        f"",
        f"## Altura (metros)",
        f"",
        f"| | Valor |",
        f"|---|---|",
        f"| Mínima | {mn_alt:.1f} m |",
        f"| Média | {med_alt:.1f} m |",
        f"| Máxima | {mx_alt:.1f} m |",
        f"",
        f"## Área de footprint (m²)",
        f"",
        f"| | Valor |",
        f"|---|---|",
        f"| Mínima | {mn_ar:.1f} m² |",
        f"| Média | {med_ar:.1f} m² |",
        f"| Máxima | {mx_ar:.1f} m² |",
        f"",
        f"## Bbox efetivo dos prédios",
        f"",
        f"```",
        f"lat: {min(lats):.6f} .. {max(lats):.6f}",
        f"lon: {min(lons):.6f} .. {max(lons):.6f}",
        f"```",
        f"",
        f"## Tipos de prédio mais comuns",
        f"",
        f"| Tipo | Quantidade |",
        f"|---|---|",
    ]
    for tipo, n in top_tipos:
        linhas.append(f"| {tipo} | {n} |")

    linhas += [
        f"",
        f"## Notas de licença",
        f"",
        f"- **Open Buildings 2.5D Temporal V1** — Google, CC BY 4.0.",
        f"  Creditar Google nos créditos do jogo.",
        f"- **OpenStreetMap** — ODbL (footprints e tags).",
    ]

    os.makedirs("build", exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas) + "\n")

    print(f"[Fase 4] Relatorio gerado: {OUTPUT}")
    print(f"  Total predios: {total}")
    print(f"  2.5D GEE: {fontes.get('2p5d',0)}  |  osm_height: {fontes.get('osm_height',0)}  |  levels: {fontes.get('levels',0)}  |  default: {fontes.get('default',0)}")


if __name__ == "__main__":
    main()
