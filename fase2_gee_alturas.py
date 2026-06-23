#!/usr/bin/env python3
"""
fase2_gee_alturas.py - Fase 2: cruza os poligonos V3 com o raster de alturas
2.5D Temporal V1 (2023) via GEE e exporta para o Drive.

Usa o V3 diretamente do catalogo GEE (sem fazer upload dos poligonos),
o que e muito mais eficiente para 100k+ features.

Fluxo:
  1. Carrega V3 filtrado por bbox (mesmo filtro da Fase 1)
  2. Carrega raster 2.5D Temporal, filtra 2023, seleciona banda building_height
  3. reduceRegions (mean) sobre os poligonos V3
  4. Exporta resultado para Drive: EarthEngine/alturas_gee_santos.csv
  5. [MANUAL] Baixe o CSV do Drive e salve em build/alturas_gee.csv
     OU rode com --converter para converter o CSV.

Uso:
  EE_PROJECT=camerasreveillon python3 fase2_gee_alturas.py
  python3 fase2_gee_alturas.py --converter build/alturas_gee.csv
"""

import json
import os
import sys
import time

EE_PROJECT = os.environ.get("EE_PROJECT", "")

INPUT_FOOTPRINTS = "build/footprints_v3.geojson"
OUTPUT_ALTURAS   = "build/alturas_gee.geojson"
DRIVE_FOLDER     = "EarthEngine"
DRIVE_FILENAME   = "alturas_gee_santos"
POLL_INTERVAL    = 30

BBOX_GEE  = [-46.380, -23.995, -46.285, -23.905]
CONFIANCA = 0.65

DATASET_2P5D = "GOOGLE/Research/open-buildings-temporal/v1"
BANDA_ALTURA = "building_height"
ESCALA_M     = 4
ANO          = 2023


def checar_dependencias():
    try:
        import ee
        return ee
    except ImportError:
        print("[ERRO] earthengine-api nao instalado. Rode: pip install earthengine-api")
        sys.exit(1)


def inicializar_gee(ee):
    if not EE_PROJECT:
        print("[ERRO] EE_PROJECT nao definido.")
        print("       Uso: EE_PROJECT=camerasreveillon python3 fase2_gee_alturas.py")
        sys.exit(1)
    try:
        ee.Initialize(project=EE_PROJECT)
        print(f"[GEE] Autenticado. Projeto: {EE_PROJECT}")
    except Exception as exc:
        print(f"[ERRO] {exc}")
        sys.exit(1)


def carregar_v3(ee):
    roi = ee.Geometry.Rectangle(BBOX_GEE)
    for versao in ["v3", "v2", "v1"]:
        dataset_id = f"GOOGLE/Research/open-buildings/{versao}/polygons"
        try:
            fc = ee.FeatureCollection(dataset_id).filterBounds(roi).limit(1)
            fc.getInfo()
            print(f"[GEE] Open Buildings {versao.upper()} encontrado.")
            return (
                ee.FeatureCollection(dataset_id)
                .filterBounds(roi)
                .filter(ee.Filter.gte("confidence", CONFIANCA))
            ), versao
        except Exception as exc:
            if any(k in str(exc).lower() for k in ["not found", "does not exist", "asset"]):
                continue
            print(f"[AVISO] {versao.upper()}: {exc}")
    print("[ERRO] Nenhuma versao do Open Buildings encontrada no GEE.")
    sys.exit(1)


def carregar_raster_2p5d(ee):
    col = (
        ee.ImageCollection(DATASET_2P5D)
        .filterDate(f"{ANO}-01-01", f"{ANO}-12-31")
        .select(BANDA_ALTURA)
    )
    n = col.size().getInfo()
    if n == 0:
        print(f"[AVISO] Sem imagens para {ANO}, usando colecao completa.")
        col = ee.ImageCollection(DATASET_2P5D).select(BANDA_ALTURA)
    else:
        print(f"[GEE] {n} cena(s) 2.5D para {ANO}.")
    return col.mosaic()


def monitorar_task(task):
    print(f"[GEE] Monitorando a cada {POLL_INTERVAL}s... (Ctrl+C para parar)")
    print(f"      Acompanhe em: https://code.earthengine.google.com/tasks")
    while True:
        try:
            time.sleep(POLL_INTERVAL)
            status = task.status()
            estado = status.get("state", "UNKNOWN")
            print(f"  [{time.strftime('%H:%M:%S')}] Status: {estado}")
            if estado == "COMPLETED":
                print(f"\n[GEE] Exportacao concluida!")
                print(f"      Arquivo no Drive: {DRIVE_FOLDER}/{DRIVE_FILENAME}.csv")
                print(f"\n[MANUAL] Baixe o CSV do Drive e salve em: build/alturas_gee.csv")
                print(f"         Depois rode: python3 fase2_gee_alturas.py --converter build/alturas_gee.csv")
                return True
            elif estado in ("FAILED", "CANCELLED"):
                print(f"[ERRO] Task {estado}: {status.get('error_message', '')}")
                return False
        except KeyboardInterrupt:
            print(f"\n[INFO] Monitoramento pausado. Task continua no GEE.")
            print(f"       Quando concluir, rode: python3 fase2_gee_alturas.py --converter build/alturas_gee.csv")
            return False


def converter_csv(caminho_csv):
    """Converte o CSV exportado pelo GEE para alturas_gee.geojson."""
    import csv

    if not os.path.exists(caminho_csv):
        print(f"[ERRO] {caminho_csv} nao encontrado.")
        sys.exit(1)

    print(f"[Fase 2] Convertendo {caminho_csv}...")

    # Carrega footprints para ter a geometria (o CSV so tem propriedades)
    if not os.path.exists(INPUT_FOOTPRINTS):
        print(f"[ERRO] {INPUT_FOOTPRINTS} nao encontrado. Rode fase1 primeiro.")
        sys.exit(1)

    with open(INPUT_FOOTPRINTS, encoding="utf-8") as f:
        gj_fp = json.load(f)

    # Indexar geometrias por v3_id (full_plus_code)
    geom_por_id = {}
    for ft in gj_fp["features"]:
        p = ft["properties"]
        geom_por_id[str(p.get("v3_id", ""))] = ft["geometry"]

    features_out = []
    nulos = 0

    with open(caminho_csv, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            # GEE exporta a media como "mean" ou "building_height_mean"
            h = row.get("mean") or row.get("building_height_mean") or row.get("building_height")
            plus_code = row.get("full_plus_code") or row.get("plus_code") or ""

            try:
                h_float = float(h) if h else None
                if h_float is not None and h_float < 1.0:
                    h_float = None
            except (ValueError, TypeError):
                h_float = None

            if h_float is None:
                nulos += 1

            features_out.append({
                "type": "Feature",
                "geometry": geom_por_id.get(plus_code),
                "properties": {
                    "v3_id":      plus_code,
                    "height_2p5d": round(h_float, 2) if h_float else None,
                }
            })

    # Adicionar v3_idx por posicao (para join com fase3)
    id_para_idx = {
        ft["properties"]["v3_id"]: ft["properties"]["v3_idx"]
        for ft in gj_fp["features"]
    }
    for ft in features_out:
        ft["properties"]["v3_idx"] = id_para_idx.get(ft["properties"]["v3_id"])

    geojson_out = {"type": "FeatureCollection", "features": features_out}
    os.makedirs("build", exist_ok=True)
    with open(OUTPUT_ALTURAS, "w", encoding="utf-8") as f:
        json.dump(geojson_out, f, ensure_ascii=False, separators=(",", ":"))

    com_altura = len(features_out) - nulos
    print(f"[Fase 2] Concluida.")
    print(f"  Total amostrados   : {len(features_out)}")
    print(f"  Com height_2p5d    : {com_altura}")
    print(f"  Sem altura (null)  : {nulos}")
    print(f"  Saida              : {OUTPUT_ALTURAS}")
    print(f"\n  Proximo passo: python3 fase3_mesclar.py")


def main():
    if "--converter" in sys.argv:
        idx = sys.argv.index("--converter")
        if idx + 1 >= len(sys.argv):
            print("[ERRO] Informe o caminho do CSV apos --converter")
            sys.exit(1)
        converter_csv(sys.argv[idx + 1])
        return

    ee = checar_dependencias()
    inicializar_gee(ee)

    print("[Fase 2] Carregando V3 e raster de alturas...")
    fc_v3, versao   = carregar_v3(ee)
    imagem_altura   = carregar_raster_2p5d(ee)

    total = fc_v3.size().getInfo()
    print(f"[GEE] {total} edificios V3 para cruzar com alturas 2.5D.")

    print("[GEE] Executando reduceRegions e criando task de exportacao...")
    cruzamento = imagem_altura.reduceRegions(
        collection=fc_v3.select(["confidence", "area_in_metres", "full_plus_code"]),
        reducer=ee.Reducer.mean(),
        scale=ESCALA_M,
    )

    task = ee.batch.Export.table.toDrive(
        collection=cruzamento,
        description="santos_alturas_2p5d",
        folder=DRIVE_FOLDER,
        fileNamePrefix=DRIVE_FILENAME,
        fileFormat="CSV",
        selectors=["full_plus_code", "mean"],
    )
    task.start()
    print(f"[GEE] Task criada: {task.id}")

    monitorar_task(task)


if __name__ == "__main__":
    main()
