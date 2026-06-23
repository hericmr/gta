# world_osm.gd — Carrega mapa real de Santos: satélite + colisões OSM + prédios 2.5D (Godot 3)
extends Node2D

const CAMINHO_JSON       = "res://maps/santos.json"
const CAMINHO_META       = "res://assets/tiles/meta.json"
const CAMINHO_2P5D       = "res://maps/santos_predios_godot.json"

# 15 px ≈ 1 metro → carro (28 px) ≈ 1.9 m de largura
const ESCALA = 15.0

const PREDIOS_OSM_POR_FRAME  = 60
const PREDIOS_2P5D_POR_FRAME = 400

# Sombra: offset em unidades pré-ESCALA por metro de altura
const SOMBRA_DIR   = Vector2(0.30, 0.60)
const SOMBRA_ALPHA = 0.28

# Perspectiva GTA 2: cores das 4 faixas de altura (roof e face/parede)
const TIER_CORES_ROOF = [
	Color(0.72, 0.70, 0.65, 0.50),  # < 6m  (1-2 andares)
	Color(0.52, 0.50, 0.50, 0.62),  # 6-15m (3-5 andares)
	Color(0.36, 0.34, 0.36, 0.72),  # 15-30m (5-10 andares)
	Color(0.22, 0.20, 0.24, 0.83),  # 30m+  (torres)
]
const TIER_CORES_FACE = [
	Color(0.52, 0.50, 0.46, 0.65),  # parede visível (mais escuro que o telhado)
	Color(0.36, 0.35, 0.35, 0.75),
	Color(0.24, 0.23, 0.24, 0.82),
	Color(0.14, 0.13, 0.16, 0.90),
]

var _dados        = null   # santos.json
var _dados_2p5d   = null   # santos_predios_godot.json
var _indice       = 0
var _indice_2p5d  = 0
var _corpo_global = null
var _fase_2p5d    = false  # true quando OSM terminou e inicia 2p5d
var _shader_mats: Array = []  # 4 ShaderMaterials (um por tier), para perspectiva GTA 2

const URL_BASE        = "https://hericmr.github.io/gta"
const URL_META        = URL_BASE + "/assets/tiles/meta.json"
const URL_JSON        = URL_BASE + "/maps/santos.json"
const URL_2P5D        = URL_BASE + "/maps/santos_predios_godot.json"

var _html5_json_ok    = false
var _html5_meta_ok    = false
var _html5_2p5d_ok    = false


func _ready():
	scale = Vector2(ESCALA, ESCALA)
	if OS.get_name() == "HTML5":
		_fetch_json()
		_fetch_meta()
		_fetch_2p5d()
	else:
		_carregar_satelite()
		_carregar_json()
		_carregar_2p5d()
		_finalizar()


func _finalizar():
	if _dados == null:
		return
	# Cria 4 ShaderMaterials de perspectiva (um por faixa de altura)
	var shader = load("res://scripts/parallax_predios.shader")
	if shader:
		for i in range(4):
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_param("vis_color", TIER_CORES_ROOF[i])
			_shader_mats.append(mat)
		print("[WorldOSM] Shader de perspectiva carregado — %d materiais." % _shader_mats.size())
	else:
		print("[WorldOSM] AVISO: parallax_predios.shader nao encontrado — predios sem perspectiva.")
	_criar_ruas_visual()
	_corpo_global = StaticBody2D.new()
	add_child(_corpo_global)
	set_process(true)


func _process(_delta):
	# Fase 1: colisões OSM (santos.json)
	if not _fase_2p5d:
		if _dados == null or _indice >= len(_dados["predios"]):
			_fase_2p5d = true
			print("[WorldOSM] %d colisões OSM prontas." % _indice)
			if _dados_2p5d == null:
				set_process(false)
			return
		var fim = min(_indice + PREDIOS_OSM_POR_FRAME, len(_dados["predios"]))
		for i in range(_indice, fim):
			_criar_colisao_osm(_dados["predios"][i]["pontos"])
		_indice = fim
		return

	# Fase 2: visuais 2.5D
	if _dados_2p5d == null or _indice_2p5d >= len(_dados_2p5d["predios"]):
		set_process(false)
		print("[WorldOSM] %d prédios 2.5D carregados." % _indice_2p5d)
		return

	var fim = min(_indice_2p5d + PREDIOS_2P5D_POR_FRAME, len(_dados_2p5d["predios"]))
	for i in range(_indice_2p5d, fim):
		_criar_predio_2p5d(_dados_2p5d["predios"][i])
	_indice_2p5d = fim


# ── HTML5: HTTPRequest ────────────────────────────────────────────────────────

func _fetch_json():
	var req = HTTPRequest.new()
	add_child(req)
	req.connect("request_completed", self, "_on_json_carregado")
	if req.request(URL_JSON) != OK:
		_fundo_fallback()
		_html5_json_ok = true
		_verificar_html5_pronto()

func _on_json_carregado(result, code, _headers, body):
	if result == OK and code == 200:
		_dados = parse_json(body.get_string_from_utf8())
		if _dados:
			print("[WorldOSM] santos.json OK — %d ruas, %d prédios" % [
				len(_dados.get("ruas", [])), len(_dados.get("predios", []))])
		else:
			_fundo_fallback()
	else:
		_fundo_fallback()
	_html5_json_ok = true
	_verificar_html5_pronto()

func _fetch_meta():
	var req = HTTPRequest.new()
	add_child(req)
	req.connect("request_completed", self, "_on_meta_carregado")
	if req.request(URL_META) != OK:
		_html5_meta_ok = true
		_verificar_html5_pronto()

func _on_meta_carregado(result, code, _headers, body):
	if result == OK and code == 200:
		var meta = parse_json(body.get_string_from_utf8())
		if meta:
			var stream = load("res://scripts/satelite_stream.gd").new()
			stream.inicializar(null, meta, "res://assets/tiles/")
			add_child(stream)
			set_meta("satelite_stream", stream)
			print("[WorldOSM] Satélite pronto (HTML5, zoom %d)" % meta["zoom"])
	else:
		print("[WorldOSM] meta.json não carregado — sem satélite")
	_html5_meta_ok = true
	_verificar_html5_pronto()

func _fetch_2p5d():
	var req = HTTPRequest.new()
	add_child(req)
	req.connect("request_completed", self, "_on_2p5d_carregado")
	if req.request(URL_2P5D) != OK:
		_html5_2p5d_ok = true
		_verificar_html5_pronto()

func _on_2p5d_carregado(result, code, _headers, body):
	if result == OK and code == 200:
		_dados_2p5d = parse_json(body.get_string_from_utf8())
		if _dados_2p5d:
			print("[WorldOSM] santos_predios_godot.json OK — %d prédios" % len(_dados_2p5d["predios"]))
	else:
		print("[WorldOSM] santos_predios_godot.json não carregado — sem 2.5D")
	_html5_2p5d_ok = true
	_verificar_html5_pronto()

func _verificar_html5_pronto():
	if _html5_json_ok and _html5_meta_ok and _html5_2p5d_ok:
		_finalizar()


# ── Desktop: File.open ────────────────────────────────────────────────────────

func _carregar_satelite():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_META):
		print("[WorldOSM] meta.json não encontrado. Rode: python3 baixar_tiles.py")
		_fundo_fallback()
		return
	arq.open(CAMINHO_META, File.READ)
	var meta = parse_json(arq.get_as_text())
	arq.close()
	var stream = load("res://scripts/satelite_stream.gd").new()
	stream.inicializar(null, meta, "res://assets/tiles/")
	add_child(stream)
	set_meta("satelite_stream", stream)
	print("[WorldOSM] Satélite pronto (zoom %d)." % meta["zoom"])

func _carregar_json():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_JSON):
		print("[WorldOSM] santos.json não encontrado. Rode importar_santos.py")
		return
	arq.open(CAMINHO_JSON, File.READ)
	_dados = parse_json(arq.get_as_text())
	arq.close()
	print("[WorldOSM] santos.json carregado.")

func _carregar_2p5d():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_2P5D):
		print("[WorldOSM] santos_predios_godot.json não encontrado — sem prédios 2.5D.")
		return
	arq.open(CAMINHO_2P5D, File.READ)
	_dados_2p5d = parse_json(arq.get_as_text())
	arq.close()
	if _dados_2p5d:
		print("[WorldOSM] santos_predios_godot.json carregado — %d prédios." % len(_dados_2p5d["predios"]))


# ── Criação de nós ────────────────────────────────────────────────────────────

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
		linha.points         = pts
		linha.default_color  = Color(1, 1, 1, 0.06)
		linha.width          = float(rua["largura"])
		linha.joint_mode     = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode   = Line2D.LINE_CAP_ROUND
		add_child(linha)

func _criar_colisao_osm(pontos):
	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))
	var forma = CollisionPolygon2D.new()
	forma.polygon = pool
	_corpo_global.add_child(forma)

func _criar_predio_2p5d(predio: Dictionary) -> void:
	var pontos   = predio["poly_px"]
	var altura_m = float(predio.get("altura_m", 8.0))

	# Coordenadas absolutas pré-ESCALA (visual.position = (0,0), WorldOSM tem scale=15)
	# Assim VERTEX no shader = coords pré-ESCALA absolutas, sem WORLD_MATRIX
	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))

	# Faixa de altura para o ShaderMaterial certo
	var tier: int
	if   altura_m < 6.0:  tier = 0
	elif altura_m < 15.0: tier = 1
	elif altura_m < 30.0: tier = 2
	else:                 tier = 3

	# ── Sombra: chão, sem perspectiva ─────────────────────────────────────────
	if altura_m > 4.0:
		var offset_s    = SOMBRA_DIR * altura_m
		var pool_sombra = PoolVector2Array()
		for v in pool:
			pool_sombra.append(v + offset_s)
		var sombra     = Polygon2D.new()
		sombra.polygon = pool_sombra
		sombra.color   = Color(0.0, 0.0, 0.0, clamp(SOMBRA_ALPHA * altura_m / 15.0, 0.06, SOMBRA_ALPHA))
		sombra.z_index = -3
		add_child(sombra)

	# ── Face/parede: base do prédio, sem perspectiva ───────────────────────────
	# Fica "atrás" do telhado; a borda não coberta pelo telhado revela a face lateral
	if altura_m > 3.0:
		var face     = Polygon2D.new()
		face.polygon = pool
		face.color   = TIER_CORES_FACE[tier]
		face.z_index = -2
		add_child(face)

	# ── Telhado: perspectiva dinâmica via shader (estilo GTA 2) ────────────────
	var visual     = Polygon2D.new()
	visual.polygon = pool
	visual.z_index = -1

	if not _shader_mats.empty():
		# Vertex colors: R = altura normalizada (lida pelo shader para calcular offset)
		var h_norm = clamp(altura_m / 100.0, 0.0, 1.0)
		var vcols  = PoolColorArray()
		for _v in pool:
			vcols.append(Color(h_norm, 0.0, 0.0, 1.0))
		visual.vertex_colors = vcols
		visual.material      = _shader_mats[tier]
	else:
		# Fallback: cor sólida (sem perspectiva, shader não disponível)
		visual.color = TIER_CORES_ROOF[tier]

	add_child(visual)


# Chamado por main.gd a cada frame — atualiza posição do player no shader
func atualizar_parallax(pos_jogo: Vector2) -> void:
	if _shader_mats.empty():
		return
	var pos_pre = pos_jogo / ESCALA
	for mat in _shader_mats:
		mat.set_shader_param("player_pos_pre", pos_pre)
