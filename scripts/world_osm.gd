# world_osm.gd — Carrega mapa real de Santos: satélite + colisões OSM (Godot 3)
extends Node2D

const CAMINHO_JSON  = "res://maps/santos.json"
const CAMINHO_META  = "res://assets/tiles/meta.json"

# 15 px ≈ 1 metro → carro (28 px) ≈ 1.9 m de largura
const ESCALA = 15.0

const COR_PREDIO = Color(0.55, 0.55, 0.60, 0.45)
const PREDIOS_POR_FRAME = 60

var _dados        = null
var _indice       = 0
var _corpo_global = null

func _ready():
	scale = Vector2(ESCALA, ESCALA)
	_carregar_satelite()
	_carregar_json()
	_finalizar()

func _finalizar():
	if _dados == null:
		return
	_criar_ruas_visual()
	_corpo_global = StaticBody2D.new()
	add_child(_corpo_global)
	set_process(true)

func _process(_delta):
	if _dados == null or _indice >= len(_dados["predios"]):
		set_process(false)
		print("[WorldOSM] %d prédios carregados." % _indice)
		return

	var fim = min(_indice + PREDIOS_POR_FRAME, len(_dados["predios"]))
	for i in range(_indice, fim):
		_criar_predio(_dados["predios"][i]["pontos"])
	_indice = fim

# ── Carregamento (File — funciona em desktop e HTML5 quando arquivos estão no .pck) ──

func _carregar_satelite():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_META):
		print("[WorldOSM] assets/tiles/meta.json não encontrado.")
		if OS.get_name() != "HTML5":
			print("[WorldOSM] Rode: python3 baixar_tiles.py")
		_fundo_fallback()
		return

	arq.open(CAMINHO_META, File.READ)
	var meta = parse_json(arq.get_as_text())
	arq.close()

	var stream = load("res://scripts/satelite_stream.gd").new()
	stream.inicializar(null, meta, "res://assets/tiles/")
	add_child(stream)
	set_meta("satelite_stream", stream)
	print("[WorldOSM] Satellite streaming pronto (zoom %d)." % meta["zoom"])

func _carregar_json():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_JSON):
		print("[WorldOSM] maps/santos.json não encontrado.")
		return
	arq.open(CAMINHO_JSON, File.READ)
	_dados = parse_json(arq.get_as_text())
	arq.close()
	print("[WorldOSM] santos.json carregado.")

# ── Helpers ──────────────────────────────────────────────────────────────────

func _fundo_fallback():
	var bg = Polygon2D.new()
	bg.polygon = PoolVector2Array([
		Vector2(-1000, -1000), Vector2(10000, -1000),
		Vector2(10000, 10000), Vector2(-1000, 10000)
	])
	bg.color = Color(0.18, 0.38, 0.65)
	add_child(bg)

func _criar_ruas_visual():
	for rua in _dados["ruas"]:
		var linha = Line2D.new()
		var pts   = PoolVector2Array()
		for p in rua["pontos"]:
			pts.append(Vector2(p[0], p[1]))
		linha.points           = pts
		linha.default_color    = Color(1, 1, 1, 0.06)
		linha.width            = float(rua["largura"])
		linha.joint_mode       = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode   = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode     = Line2D.LINE_CAP_ROUND
		add_child(linha)

func _criar_predio(pontos):
	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))

	var forma = CollisionPolygon2D.new()
	forma.polygon = pool
	_corpo_global.add_child(forma)

	var visual = Polygon2D.new()
	visual.polygon = pool
	visual.color   = COR_PREDIO
	add_child(visual)
