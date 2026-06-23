#!/usr/bin/env python3
"""
fase1_footprints.py - Fase 1: exporta poligonos Open Buildings V3 para o
Google Drive via GEE (async), monitora o job e converte o resultado.

Fluxo:
  1. Cria task de exportacao no GEE (leva segundos)
  2. Monitora status ate concluir (tipicamente 5-15 min para 100k features)
  3. Quando pronto, o arquivo aparece no Google Drive em: EarthEngine/footprints_v3_santos.geojson
  4. [MANUAL] Baixe o arquivo do Drive e salve em build/footprints_v3.geojson
     OU rode com --converter para converter um CSV ja baixado.

Uso:
  EE_PROJECT=camerasreveillon python3 fase1_footprints.py
  EE_PROJECT=camerasreveillon python3 fase1_footprints.py --converter caminho.csv
"""

import json
import os
import sys
import time

EE_PROJECT = os.environ.get("EE_PROJECT", "")

OUTPUT          = "build/footprints_v3.geojson"
BBOX_GEE        = [-46.380, -23.995, -46.285, -23.905]
CONFIANCA       = 0.65
DRIVE_FOLDER    = "EarthEngine"
DRIVE_FILENAME  = "footprints_v3_santos"
POLL_INTERVAL   = 30   # segundos entre checagens de status


def checar_dependencias():
    try:
        import ee
        return ee
    except ImportError:
        print("[ERRO] earthengine-api nao instalado. Rode: pip install earthengine-api")
        sys.exit(1)


def inicializar_gee(ee):
    if not EE_PROJECT:
        print("[ERRO] Variavel EE_PROJECT nao definida.")
        print("       Uso: EE_PROJECT=camerasreveillon python3 fase1_footprints.py")
        sys.exit(1)
    try:
        ee.Initialize(project=EE_PROJECT)
        print(f"[GEE] Autenticado. Projeto: {EE_PROJECT}")
    except Exception as exc:
        msg = str(exc)
        print(f"[ERRO] Falha ao inicializar GEE: {msg}")
        if "authenticate" in msg.lower():
            print("       Execute: earthengine authenticate")
        elif "not registered" in msg.lower():
            print("       Registre o projeto em: https://console.cloud.google.com/earth-engine/")
        sys.exit(1)


def detectar_versao(ee, roi):
    for versao in ["v3", "v2", "v1"]:
        dataset_id = f"GOOGLE/Research/open-buildings/{versao}/polygons"
        try:
            fc = ee.FeatureCollection(dataset_id).filterBounds(roi).limit(1)
            fc.getInfo()
            print(f"[GEE] Open Buildings {versao.upper()} encontrado.")
            return ee.FeatureCollection(dataset_id), versao
        except Exception as exc:
            msg = str(exc).lower()
            if "not found" in msg or "does not exist" in msg or "asset" in msg:
                print(f"[GEE] {versao.upper()} nao disponivel, tentando anterior...")
            else:
                print(f"[AVISO] {versao.upper()}: {exc}")
    print("[ERRO] Nenhuma versao do Open Buildings encontrada no catalogo GEE.")
    sys.exit(1)


def exportar_para_drive(ee, fc_filtrada, versao):
    """Cria task de exportacao no GEE e monitora ate concluir."""
    total = fc_filtrada.size().getInfo()
    print(f"[GEE] {total} edificios dentro do bbox com confidence >= {CONFIANCA}.")

    # Seleciona apenas campos necessarios para reduzir tamanho do arquivo
    campos = ["confidence", "area_in_metres", "full_plus_code"]
    try:
        fc_export = fc_filtrada.select(campos)
    except Exception:
        fc_export = fc_filtrada  # alguns versoes tem nomes diferentes

    task = ee.batch.Export.table.toDrive(
        collection=fc_export,
        description=f"santos_buildings_{versao}",
        folder=DRIVE_FOLDER,
        fileNamePrefix=DRIVE_FILENAME,
        fileFormat="GeoJSON",
    )
    task.start()
    task_id = task.id
    print(f"[GEE] Task criada: {task_id}")
    print(f"[GEE] Monitorando a cada {POLL_INTERVAL}s... (Ctrl+C para parar e checar no Drive manualmente)")
    print(f"      Acompanhe em: https://code.earthengine.google.com/tasks")

    while True:
        time.sleep(POLL_INTERVAL)
        try:
            status = task.status()
            estado = status.get("state", "UNKNOWN")
            print(f"  [{time.strftime('%H:%M:%S')}] Status: {estado}")

            if estado == "COMPLETED":
                print(f"\n[GEE] Exportacao concluida!")
                print(f"      Arquivo no Google Drive: {DRIVE_FOLDER}/{DRIVE_FILENAME}.geojson")
                print(f"\n[MANUAL] Baixe o arquivo do Drive e salve em: build/footprints_v3.geojson")
                print(f"         Depois rode: python3 fase1_footprints.py --converter build/footprints_v3.geojson")
                return True

            elif estado in ("FAILED", "CANCELLED"):
                erro = status.get("error_message", "sem detalhes")
                print(f"[ERRO] Task {estado}: {erro}")
                return False

        except KeyboardInterrupt:
            print(f"\n[INFO] Monitoramento interrompido.")
            print(f"       A task continua rodando no GEE.")
            print(f"       Acompanhe em: https://code.earthengine.google.com/tasks")
            print(f"       Quando concluir, baixe o arquivo do Drive e rode:")
            print(f"       python3 fase1_footprints.py --converter caminho/do/arquivo.geojson")
            return False


def converter_geojson(caminho_entrada):
    """Normaliza o GeoJSON exportado pelo GEE para o formato esperado pelas fases seguintes."""
    print(f"[Fase 1] Convertendo {caminho_entrada}...")

    if not os.path.exists(caminho_entrada):
        print(f"[ERRO] Arquivo nao encontrado: {caminho_entrada}")
        sys.exit(1)

    with open(caminho_entrada, encoding="utf-8") as f:
        gj = json.load(f)

    features_in  = gj.get("features", [])
    features_out = []

    for idx, ft in enumerate(features_in):
        geom  = ft.get("geometry")
        props = ft.get("properties", {})

        if geom is None:
            continue

        tipo   = geom.get("type", "")
        coords = geom.get("coordinates", [[]])

        if tipo == "MultiPolygon":
            maior  = max(coords, key=lambda c: len(c[0]) if c else 0)
            coords = maior
            tipo   = "Polygon"
        elif tipo != "Polygon":
            continue

        if not coords or not coords[0]:
            continue

        confidence = props.get("confidence") or props.get("confidence_score")
        area_v3    = props.get("area_in_metres") or props.get("area_m2")
        v3_id      = props.get("full_plus_code") or props.get("plus_code") or str(idx)

        features_out.append({
            "type": "Feature",
            "geometry": {"type": tipo, "coordinates": coords},
            "properties": {
                "v3_idx":     idx,
                "v3_id":      v3_id,
                "versao":     "v3",
                "confidence": round(float(confidence), 4) if confidence is not None else None,
                "area_m2_v3": round(float(area_v3), 1)   if area_v3    is not None else None,
            }
        })

    geojson_out = {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "EPSG:4326"}},
        "features": features_out
    }

    os.makedirs("build", exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(geojson_out, f, ensure_ascii=False, separators=(",", ":"))

    print(f"[Fase 1] Concluida.")
    print(f"  Edificios convertidos : {len(features_out)}")
    print(f"  Saida                 : {OUTPUT}")
    print(f"\n  Proximo passo: EE_PROJECT={EE_PROJECT or 'SEU_PROJECT'} python3 fase2_gee_alturas.py")


def main():
    if "--converter" in sys.argv:
        idx = sys.argv.index("--converter")
        if idx + 1 >= len(sys.argv):
            print("[ERRO] Informe o caminho do arquivo apos --converter")
            sys.exit(1)
        converter_geojson(sys.argv[idx + 1])
        return

    ee = checar_dependencias()
    inicializar_gee(ee)

    roi = ee.Geometry.Rectangle(BBOX_GEE)
    dataset_base, versao = detectar_versao(ee, roi)

    fc_filtrada = (
        dataset_base
        .filterBounds(roi)
        .filter(ee.Filter.gte("confidence", CONFIANCA))
    )

    exportar_para_drive(ee, fc_filtrada, versao)


if __name__ == "__main__":
    main()
