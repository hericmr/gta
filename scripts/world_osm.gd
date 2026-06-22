# world_osm.gd — Carrega mapa real de Santos: satélite + colisões OSM (Godot 3)
extends Node2D

const CAMINHO_JSON  = "res://maps/santos.json"
const CAMINHO_IMG   = "res://assets/satelite_santos.png"
const CAMINHO_META  = "res://assets/satelite_meta.json"

# 15 px ≈ 1 metro → carro (28 px) ≈ 1.9 m de largura
const ESCALA = 15.0

# Prédios com leve tint semi-transparente para destacar colisões sobre o satélite
const COR_PREDIO = Color(0.55, 0.55, 0.60, 0.45)

const PREDIOS_POR_FRAME = 60

var _dados        = null
var _indice       = 0
var _corpo_global = null

func _ready():
	scale = Vector2(ESCALA, ESCALA)

	_carregar_satelite()
	_carregar_json()

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

# ── Satélite ────────────────────────────────────────────────────────────────

func _carregar_satelite():
	var arq = File.new()
	if not arq.file_exists("res://assets/tiles/meta.json"):
		print("[WorldOSM] assets/tiles/meta.json não encontrado.")
		print("[WorldOSM] Rode: python3 baixar_tiles.py")
		_fundo_fallback()
		return

	arq.open("res://assets/tiles/meta.json", File.READ)
	var meta = parse_json(arq.get_as_text())
	arq.close()

	var stream = load("res://scripts/satelite_stream.gd").new()
	stream.inicializar(null, meta, "res://assets/tiles/")  # carro conectado depois pelo main.gd
	add_child(stream)

	# Guarda referência para main.gd poder passar o carro
	set_meta("satelite_stream", stream)
	print("[WorldOSM] Satellite streaming pronto (zoom %d, raio %d tiles)." % [meta["zoom"], 4])

func _fundo_fallback():
	var bg = Polygon2D.new()
	bg.polygon = PoolVector2Array([
		Vector2(-1000, -1000), Vector2(10000, -1000),
		Vector2(10000, 10000), Vector2(-1000, 10000)
	])
	bg.color = Color(0.18, 0.38, 0.65)
	add_child(bg)

# ── JSON OSM ────────────────────────────────────────────────────────────────

func _carregar_json():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_JSON):
		print("[WorldOSM] maps/santos.json não encontrado. Rode importar_santos.py")
		return
	arq.open(CAMINHO_JSON, File.READ)
	_dados = parse_json(arq.get_as_text())
	arq.close()

func _criar_ruas_visual():
	# Line2D levemente mais claros que o satélite para indicar colisão futura
	# (opcional — pode remover se preferir só o satélite limpo)
	for rua in _dados["ruas"]:
		var linha = Line2D.new()
		var pts   = PoolVector2Array()
		for p in rua["pontos"]:
			pts.append(Vector2(p[0], p[1]))
		linha.points           = pts
		linha.default_color    = Color(1, 1, 1, 0.06)   # branco bem sutil
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

	# Overlay semi-transparente para indicar que é uma parede sólida
	var visual = Polygon2D.new()
	visual.polygon = pool
	visual.color   = COR_PREDIO
	add_child(visual)
