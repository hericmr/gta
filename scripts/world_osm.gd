# world_osm.gd — Carrega mapa real de Santos: satélite + colisões OSM + prédios 2.5D (Godot 3)
extends Node2D

const CAMINHO_JSON       = "res://maps/santos.json"
const CAMINHO_META       = "res://assets/tiles/meta.json"
const CAMINHO_2P5D       = "res://maps/santos_predios_godot.json"
const CAMINHO_FEATURES   = "res://maps/santos_features.json"

# 15 px ≈ 1 metro → carro (28 px) ≈ 1.9 m de largura
const ESCALA = 15.0

# Lazy loading por chunks: só carrega prédios perto do player
const CHUNK_SIZE_PRE = 500    # unidades pré-ESCALA por chunk (= 7500 px de jogo)
const RAIO_CHUNKS    = 1      # carrega 3×3 chunks ao redor do player

# Cores base por tipo de prédio: [roof, wall, face]
# Cada tier de altura escurece as cores pelo fator TIER_ESCURO.
const TIPO_CORES = {
	"residencial": [Color(0.90, 0.78, 0.62), Color(0.70, 0.57, 0.42), Color(0.48, 0.37, 0.25)],
	"comercial":   [Color(0.70, 0.78, 0.92), Color(0.52, 0.60, 0.76), Color(0.34, 0.42, 0.58)],
	"industrial":  [Color(0.72, 0.57, 0.40), Color(0.54, 0.40, 0.26), Color(0.36, 0.25, 0.15)],
	"publico":     [Color(0.92, 0.85, 0.50), Color(0.74, 0.66, 0.35), Color(0.52, 0.45, 0.20)],
	"garagem":     [Color(0.65, 0.67, 0.72), Color(0.50, 0.52, 0.58), Color(0.34, 0.36, 0.42)],
	"geral":       [Color(0.78, 0.74, 0.68), Color(0.60, 0.55, 0.49), Color(0.40, 0.36, 0.30)],
}
const TIER_ESCURO = [1.0, 0.82, 0.65, 0.50]  # fator por tier (< 6m, 6-15m, 15-30m, 30m+)
const COR_BORDA   = Color(0.10, 0.08, 0.06, 0.85)

var _dados        = null   # santos.json
var _dados_2p5d   = null   # santos_predios_godot.json
var _corpo_global = null   # StaticBody2D de fallback (não usada para prédios lazy)
var _predios_dinamicos: Array = []  # [{pool, wall_px, centro, roof, quads}] carregados

# Chunk system
var _predios_chunk:      Dictionary = {}  # "cx_cy" → Array de dados OSM
var _predios_2p5d_chunk: Dictionary = {}  # "cx_cy" → Array de dados 2.5D
var _corpos_chunk:       Dictionary = {}  # "cx_cy" → StaticBody2D com colisões
var _visuais_chunk:      Dictionary = {}  # "cx_cy" → Array de nodes visuais 2.5D
var _dinamicos_chunk:    Dictionary = {}  # "cx_cy" → Array de dicts parallax
var _chunk_player:       Vector2    = Vector2(-999.0, -999.0)

const TEX_GRAMA_SRC = preload("res://assets/texturas/grass03.png")
const TILE_GRAMA    = 35.0   # unidades pré-escala por repetição de tile (35 u = 525 px de jogo)

const URL_BASE         = "https://hericmr.github.io/gta"
const URL_META         = URL_BASE + "/assets/tiles/meta.json"
const URL_JSON         = URL_BASE + "/maps/santos.json"
const URL_2P5D         = URL_BASE + "/maps/santos_predios_godot.json"
const URL_FEATURES     = URL_BASE + "/maps/santos_features.json"

var _html5_json_ok     = false
var _html5_meta_ok     = false
var _html5_2p5d_ok     = false
var _html5_features_ok = false

var _dados_features    = null


func _ready():
	scale = Vector2(ESCALA, ESCALA)
	if OS.get_name() == "HTML5":
		_fetch_json()
		_fetch_meta()
		_fetch_2p5d()
		_fetch_features()
	else:
		_carregar_satelite()
		_carregar_json()
		_carregar_2p5d()
		_carregar_features()
		_finalizar()


func _finalizar():
	if _dados == null:
		return
	if _dados_features != null:
		_criar_features(_dados_features)
	_criar_ruas_visual()
	_corpo_global = StaticBody2D.new()
	add_child(_corpo_global)
	# Indexa prédios em chunks; carregamento acontece via atualizar_parallax()
	_indexar_predios_por_chunk()
	_indexar_predios_2p5d_por_chunk()
	print("[WorldOSM] %d prédios OSM e %d 2.5D indexados em chunks." % [
		_dados["predios"].size(), (_dados_2p5d["predios"].size() if _dados_2p5d else 0)])
	_atualizar_chunks()   # carrega chunks iniciais (pode estar em (-999,-999) ainda)


# ── Chunk system ──────────────────────────────────────────────────────────────

func _chunk_key_pre(px: float, py: float) -> String:
	return str(int(px / CHUNK_SIZE_PRE)) + "_" + str(int(py / CHUNK_SIZE_PRE))


func _indexar_predios_por_chunk() -> void:
	if _dados == null:
		return
	for predio in _dados["predios"]:
		var pts = predio["pontos"]
		if pts.empty():
			continue
		var cx = 0.0; var cy = 0.0
		for p in pts:
			cx += p[0]; cy += p[1]
		cx /= pts.size(); cy /= pts.size()
		var k = _chunk_key_pre(cx, cy)
		if not _predios_chunk.has(k):
			_predios_chunk[k] = []
		_predios_chunk[k].append(predio)


func _indexar_predios_2p5d_por_chunk() -> void:
	if _dados_2p5d == null:
		return
	for predio in _dados_2p5d["predios"]:
		var pts = predio.get("poly_px", [])
		if pts.empty():
			continue
		var cx = 0.0; var cy = 0.0
		for p in pts:
			cx += p[0]; cy += p[1]
		cx /= pts.size(); cy /= pts.size()
		var k = _chunk_key_pre(cx, cy)
		if not _predios_2p5d_chunk.has(k):
			_predios_2p5d_chunk[k] = []
		_predios_2p5d_chunk[k].append(predio)


func _atualizar_chunks() -> void:
	var novos: Dictionary = {}
	var cx0 = int(_chunk_player.x)
	var cy0 = int(_chunk_player.y)
	for dx in range(-RAIO_CHUNKS, RAIO_CHUNKS + 1):
		for dy in range(-RAIO_CHUNKS, RAIO_CHUNKS + 1):
			novos[str(cx0 + dx) + "_" + str(cy0 + dy)] = true

	# Descarrega chunks fora do raio
	for k in _corpos_chunk.keys():
		if not novos.has(k):
			_descarregar_chunk(k)

	# Carrega novos chunks
	for k in novos.keys():
		if not _corpos_chunk.has(k):
			_carregar_chunk(k)


func _carregar_chunk(k: String) -> void:
	var corpo = StaticBody2D.new()
	add_child(corpo)
	_corpos_chunk[k] = corpo

	for predio in _predios_chunk.get(k, []):
		_criar_colisao_em(corpo, predio["pontos"])

	var visuais:   Array = []
	var dinamicos: Array = []
	for predio in _predios_2p5d_chunk.get(k, []):
		var entry = _criar_predio_2p5d_lazy(corpo, predio, visuais)
		if entry:
			dinamicos.append(entry)
			_predios_dinamicos.append(entry)
	_visuais_chunk[k]   = visuais
	_dinamicos_chunk[k] = dinamicos


func _descarregar_chunk(k: String) -> void:
	# Remove entradas de parallax
	for entry in _dinamicos_chunk.get(k, []):
		_predios_dinamicos.erase(entry)
	_dinamicos_chunk.erase(k)

	# Libera nós visuais 2.5D (borda, face, quads, telhado)
	for no in _visuais_chunk.get(k, []):
		if is_instance_valid(no):
			no.queue_free()
	_visuais_chunk.erase(k)

	# Libera StaticBody2D → remove colisões do motor de física
	if _corpos_chunk.has(k) and is_instance_valid(_corpos_chunk[k]):
		_corpos_chunk[k].queue_free()
	_corpos_chunk.erase(k)


func _criar_colisao_em(corpo: StaticBody2D, pontos) -> void:
	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))
	var forma = CollisionPolygon2D.new()
	forma.polygon = pool
	corpo.add_child(forma)


func _criar_predio_2p5d_lazy(corpo: StaticBody2D, predio: Dictionary, visuais_list: Array):
	var pontos = predio.get("poly_px", [])
	if pontos.empty():
		return null
	var altura_m = float(predio.get("altura_m", 8.0))
	var tipo     = predio.get("tipo", "geral")

	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))

	var colisao = CollisionPolygon2D.new()
	colisao.polygon = pool
	corpo.add_child(colisao)

	var tier: int
	if   altura_m < 6.0:  tier = 0
	elif altura_m < 15.0: tier = 1
	elif altura_m < 30.0: tier = 2
	else:                 tier = 3

	var wall_px = clamp(altura_m * 0.45, 2.0, 22.0)
	var n       = pool.size()
	var cores   = TIPO_CORES.get(tipo, TIPO_CORES["geral"])
	var escuro  = TIER_ESCURO[tier]
	var c_roof  = Color(cores[0].r * escuro, cores[0].g * escuro, cores[0].b * escuro)
	var c_wall  = Color(cores[1].r * escuro, cores[1].g * escuro, cores[1].b * escuro)
	var c_face  = Color(cores[2].r * escuro, cores[2].g * escuro, cores[2].b * escuro)

	var borda = Line2D.new()
	for v in pool:
		borda.add_point(v)
	borda.add_point(pool[0])
	borda.default_color  = COR_BORDA
	borda.width          = 0.7
	borda.joint_mode     = Line2D.LINE_JOINT_ROUND
	borda.begin_cap_mode = Line2D.LINE_CAP_ROUND
	borda.end_cap_mode   = Line2D.LINE_CAP_ROUND
	borda.z_index        = -4
	add_child(borda)
	visuais_list.append(borda)

	var face = Polygon2D.new()
	face.polygon = pool
	face.color   = c_face
	face.z_index = -3
	add_child(face)
	visuais_list.append(face)

	var quads = []
	for i in range(n):
		var q     = Polygon2D.new()
		q.color   = c_wall
		q.z_index = -2
		add_child(q)
		quads.append(q)
		visuais_list.append(q)

	var visual = Polygon2D.new()
	visual.polygon = pool
	visual.color   = c_roof
	visual.z_index = -1
	add_child(visual)
	visuais_list.append(visual)

	return {
		"pool":    pool,
		"wall_px": wall_px,
		"centro":  _centroide(pool),
		"roof":    visual,
		"quads":   quads,
	}


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
			stream.inicializar(null, meta, URL_BASE + "/assets/tiles/")
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

func _fetch_features():
	var req = HTTPRequest.new()
	add_child(req)
	req.connect("request_completed", self, "_on_features_carregado")
	if req.request(URL_FEATURES) != OK:
		_html5_features_ok = true
		_verificar_html5_pronto()

func _on_features_carregado(result, code, _headers, body):
	if result == OK and code == 200:
		_dados_features = parse_json(body.get_string_from_utf8())
		if _dados_features:
			print("[WorldOSM] santos_features.json OK — canais:%d verde:%d praia:%d agua:%d porto:%d mar:%d" % [
				len(_dados_features.get("canais", [])),
				len(_dados_features.get("verde",  [])),
				len(_dados_features.get("praia",  [])),
				len(_dados_features.get("agua",   [])),
				len(_dados_features.get("porto",  [])),
				len(_dados_features.get("mar",    []))])
	else:
		print("[WorldOSM] santos_features.json não carregado — sem features OSM")
	_html5_features_ok = true
	_verificar_html5_pronto()

func _verificar_html5_pronto():
	if _html5_json_ok and _html5_meta_ok and _html5_2p5d_ok and _html5_features_ok:
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

func _carregar_features():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_FEATURES):
		print("[WorldOSM] santos_features.json não encontrado — sem features OSM.")
		return
	arq.open(CAMINHO_FEATURES, File.READ)
	_dados_features = parse_json(arq.get_as_text())
	arq.close()
	if _dados_features:
		print("[WorldOSM] santos_features.json carregado — canais:%d verde:%d praia:%d mar:%d." % [
			len(_dados_features.get("canais", [])),
			len(_dados_features.get("verde",  [])),
			len(_dados_features.get("praia",  [])),
			len(_dados_features.get("mar",    []))])


# ── Criação de nós ────────────────────────────────────────────────────────────

func _fundo_fallback():
	var bg = Polygon2D.new()
	bg.polygon = PoolVector2Array([
		Vector2(-1000, -1000), Vector2(10000, -1000),
		Vector2(10000, 16000), Vector2(-1000, 16000)
	])
	bg.color = Color(0.18, 0.38, 0.65)
	add_child(bg)

func _z_rua(largura: float) -> int:
	# Calçada = tier*2 - 30  →  -30..-20
	# Rua     = tier*2 - 29  →  -29..-19
	# Prédios: -3, -2, -1  |  Entidades: 0+
	if largura >= 11: return 5
	if largura >= 7:  return 4
	if largura >= 5:  return 3
	if largura >= 4:  return 2
	if largura >= 3:  return 1
	return 0

func _ordenar_por_largura(a, b) -> bool:
	return float(a["largura"]) < float(b["largura"])

func _criar_ruas_visual():
	# Ordena da menor para a maior largura: avenidas ficam no topo
	var ruas_ordenadas = _dados["ruas"].duplicate()
	ruas_ordenadas.sort_custom(self, "_ordenar_por_largura")

	# Calçadas (largura aumentada)
	for rua in ruas_ordenadas:
		var largura = float(rua["largura"])
		var cor_calcada = Color(1.00, 0.86, 0.86)
		var extra = 10.0
		var calcada = Line2D.new()
		var pts = PoolVector2Array()
		for p in rua["pontos"]: pts.append(Vector2(p[0], p[1]))
		calcada.points = pts
		calcada.default_color = cor_calcada
		calcada.width = _largura_calcada(largura, extra)
		calcada.joint_mode = Line2D.LINE_JOINT_ROUND
		calcada.begin_cap_mode = Line2D.LINE_CAP_ROUND
		calcada.end_cap_mode = Line2D.LINE_CAP_ROUND
		calcada.z_index = _z_rua(largura) * 2 - 30
		add_child(calcada)

	# Ruas
	for rua in ruas_ordenadas:
		var largura = float(rua["largura"])
		var linha = Line2D.new()
		var pts = PoolVector2Array()
		for p in rua["pontos"]: pts.append(Vector2(p[0], p[1]))
		linha.points = pts
		linha.default_color = _cor_rua(largura)
		linha.width = _mult_rua(largura) * largura
		linha.joint_mode = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode = Line2D.LINE_CAP_ROUND
		linha.z_index = _z_rua(largura) * 2 - 29
		add_child(linha)

func _largura_calcada(largura: float, extra: float) -> float:
	if largura >= 11: return largura * 1.40 + extra * 2
	if largura >= 7 and largura <= 10: return largura * 1.55 + extra * 2
	if largura == 6: return largura * 1.00 + extra * 2
	return largura + extra * 2

func _cor_rua(largura: float) -> Color:
	if largura >= 11: return Color(0.91, 0.82, 0.38, 0.90)
	if largura >= 7 and largura <= 10: return Color(0.00, 0.00, 0.00, 1.00)
	if largura == 6: return Color(0.00, 0.00, 0.00, 0.55)
	if largura >= 4 and largura <= 5: return Color(0.00, 0.00, 0.00, 1.00)
	if largura == 3: return Color(0.27, 0.27, 0.27, 1.00)
	if largura <= 2: return Color(0.98, 1.00, 0.75, 1.00)
	return Color(0.3, 0.3, 0.3, 0.3)

func _mult_rua(largura: float) -> float:
	if largura >= 11: return 1.40
	if largura >= 7 and largura <= 10: return 1.55
	if largura == 6: return 1.00
	if largura >= 4 and largura <= 5: return 1.90
	if largura == 3: return 0.50
	if largura <= 2: return 3.00
	return 1.0

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
	var tipo     = predio.get("tipo", "geral")

	var pool = PoolVector2Array()
	for p in pontos:
		pool.append(Vector2(p[0], p[1]))

	# ── Colisão ────────────────────────────────────────────────────────────────
	var colisao = CollisionPolygon2D.new()
	colisao.polygon = pool
	_corpo_global.add_child(colisao)

	# Tier de altura e cores por tipo
	var tier: int
	if   altura_m < 6.0:  tier = 0
	elif altura_m < 15.0: tier = 1
	elif altura_m < 30.0: tier = 2
	else:                 tier = 3

	var wall_px = clamp(altura_m * 0.45, 2.0, 22.0)
	var n       = pool.size()

	var cores   = TIPO_CORES.get(tipo, TIPO_CORES["geral"])
	var escuro  = TIER_ESCURO[tier]
	var c_roof  = Color(cores[0].r * escuro, cores[0].g * escuro, cores[0].b * escuro)
	var c_wall  = Color(cores[1].r * escuro, cores[1].g * escuro, cores[1].b * escuro)
	var c_face  = Color(cores[2].r * escuro, cores[2].g * escuro, cores[2].b * escuro)

	# ── Borda escura (z=-4, metade externa visível ao redor do prédio) ────────
	var borda = Line2D.new()
	for v in pool:
		borda.add_point(v)
	borda.add_point(pool[0])  # fecha o contorno
	borda.default_color  = COR_BORDA
	borda.width          = 0.7
	borda.joint_mode     = Line2D.LINE_JOINT_ROUND
	borda.begin_cap_mode = Line2D.LINE_CAP_ROUND
	borda.end_cap_mode   = Line2D.LINE_CAP_ROUND
	borda.z_index        = -4
	add_child(borda)

	# ── Base — fixa na posição original (z=-3) ────────────────────────────────
	var face     = Polygon2D.new()
	face.polygon = pool
	face.color   = c_face
	face.z_index = -3
	add_child(face)

	# ── Quads de parede — ligam base ao telhado (z=-2) ───────────────────────
	var quads = []
	for i in range(n):
		var q     = Polygon2D.new()
		q.color   = c_wall
		q.z_index = -2
		add_child(q)
		quads.append(q)

	# ── Telhado — atualizado por frame via atualizar_parallax (z=-1) ─────────
	var visual     = Polygon2D.new()
	visual.polygon = pool
	visual.color   = c_roof
	visual.z_index = -1
	add_child(visual)

	_predios_dinamicos.append({
		"pool":    pool,
		"wall_px": wall_px,
		"centro":  _centroide(pool),
		"roof":    visual,
		"quads":   quads,
	})


# ── Features OSM ─────────────────────────────────────────────────────────────
# z-index: satellite=-10 | mar=-9 | porto=-9 | praia=-8 | verde=-8 | agua=-7 | canais=-6
# Features ficam acima do satélite (z=-10) e abaixo dos prédios 2.5D (z=-3→-1).
# Dentro do mesmo z_index, nós adicionados depois ficam na frente (verde sobre praia).

func _tex_repetida(src: Texture) -> ImageTexture:
	var img = src.get_data()
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT | Texture.FLAG_FILTER)
	return tex


func _criar_features(dados: Dictionary) -> void:
	# Mar / Oceano Atlântico (z=-9) — abaixo da praia e dos jardins
	for f in dados.get("mar", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.12, 0.35, 0.68, 0.70)
		poly.z_index = -9
		add_child(poly)

	# Porto/industrial (z=-9, mesmo nível do mar mas adicionado depois → fica na frente)
	for f in dados.get("porto", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.38, 0.32, 0.28, 0.75)
		poly.z_index = -9
		add_child(poly)

	# Praia — areia (z=-8, adicionada antes do verde → verde (jardins) fica na frente)
	for f in dados.get("praia", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.87, 0.82, 0.62, 0.80)
		poly.z_index = -8
		add_child(poly)

	# Parques e jardins (z=-8) — textura de grama com tiling
	var tex_grama = _tex_repetida(TEX_GRAMA_SRC)
	for f in dados.get("verde", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		var uvs  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
			uvs.append(Vector2(p[0] / TILE_GRAMA, p[1] / TILE_GRAMA))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.uv      = uvs
		poly.texture = tex_grama
		poly.color   = Color(1.0, 1.0, 1.0, 0.92)
		poly.z_index = -8
		add_child(poly)

	# Corpos d'água — polígonos (z=-7)
	for f in dados.get("agua", []):
		var poly = Polygon2D.new()
		var pts  = PoolVector2Array()
		for p in f["poly_px"]:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() < 3:
			continue
		poly.polygon = pts
		poly.color   = Color(0.18, 0.45, 0.72, 0.85)
		poly.z_index = -7
		add_child(poly)

	# Canais — linhas largas (z=-6)
	for c in dados.get("canais", []):
		var pts = c["pontos"]
		if pts.size() < 2:
			continue
		var linha = Line2D.new()
		for p in pts:
			linha.add_point(Vector2(p[0], p[1]))
		linha.default_color  = Color(0.18, 0.50, 0.78, 0.90)
		linha.width          = c.get("largura", 15.0)
		linha.joint_mode     = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode   = Line2D.LINE_CAP_ROUND
		linha.z_index        = -6
		add_child(linha)

	print("[WorldOSM] Features: mar=%d porto=%d praia=%d verde=%d agua=%d canais=%d" % [
		len(dados.get("mar",    [])),
		len(dados.get("porto",  [])),
		len(dados.get("praia",  [])),
		len(dados.get("verde",  [])),
		len(dados.get("agua",   [])),
		len(dados.get("canais", []))])


func _centroide(pool: PoolVector2Array) -> Vector2:
	var c = Vector2.ZERO
	for v in pool:
		c += v
	return c / pool.size()


# Chamado por main.gd a cada frame — atualiza chunks e parallax dos prédios 2.5D
func atualizar_parallax(pos_jogo: Vector2) -> void:
	# Lazy loading: verifica se o player mudou de chunk
	var pos_pre    = pos_jogo / ESCALA
	var chunk_novo = Vector2(int(pos_pre.x / CHUNK_SIZE_PRE), int(pos_pre.y / CHUNK_SIZE_PRE))
	if chunk_novo != _chunk_player:
		_chunk_player = chunk_novo
		_atualizar_chunks()

	if _predios_dinamicos.empty():
		return
	var raio2 = 250.0 * 250.0  # só atualiza prédios dentro de ~250 unidades pré-ESCALA

	for dados in _predios_dinamicos:
		var centro: Vector2 = dados.centro
		if centro.distance_squared_to(pos_pre) > raio2:
			continue

		var dir     = (centro - pos_pre).normalized()
		var wall_px: float          = dados.wall_px
		var offset                  = dir * wall_px
		var pool:   PoolVector2Array = dados.pool
		var n                       = pool.size()

		# Atualiza telhado
		var roof_pts = PoolVector2Array()
		for v in pool:
			roof_pts.append(v + offset)
		dados.roof.polygon = roof_pts

		# Atualiza quads base→telhado
		var quads: Array = dados.quads
		for i in range(n):
			var a = pool[i]
			var b = pool[(i + 1) % n]
			quads[i].polygon = PoolVector2Array([a, b, b + offset, a + offset])
