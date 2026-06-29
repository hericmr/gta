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
var _tex_pontilhado = null
var _corpo_global = null   # StaticBody2D de fallback (não usada para prédios lazy)
var _predios_dinamicos: Array = []  # [{pool, wall_px, centro, roof, quads}] carregados
var _ruas_nomeadas:     Array = []  # [{nome, pts: PoolVector2Array}]
var _ruas_nomeadas_chunk: Dictionary = {}  # "cx_cy" → Array de {nome, pts} para busca espacial

# Chunk system
var _predios_chunk:      Dictionary = {}  # "cx_cy" → Array de dados OSM
var _predios_2p5d_chunk: Dictionary = {}  # "cx_cy" → Array de dados 2.5D
var _arvores_chunk:      Dictionary = {}  # "cx_cy" → Array de Vector2 (coordenadas pré-escala)
var _corpos_chunk:       Dictionary = {}  # "cx_cy" → StaticBody2D com colisões
var _visuais_chunk:      Dictionary = {}  # "cx_cy" → Array de nodes visuais 2.5D
var _dinamicos_chunk:    Dictionary = {}  # "cx_cy" → Array de dicts parallax
var _chunk_player:       Vector2    = Vector2(-999.0, -999.0)

var _tex_arvore_procedural: Texture = null
var _tex_sombra_procedural: Texture = null

# Mobile: flags de performance
var _is_mobile:      bool = false
var _round_prec:     int  = 32
var _parallax_frame: int  = 0

const MapFeatures = preload("res://scripts/map_features.gd")

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
var _dados_meta        = null


func _ready():
	_is_mobile = OS.has_touchscreen_ui_hint()
	_round_prec = 8 if _is_mobile else 32
	scale = Vector2(ESCALA, ESCALA)
	if OS.get_name() == "HTML5":
		_fetch_json()
		_fetch_meta()
		_fetch_2p5d()
		_fetch_features()
	else:
		_fundo_fallback()
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
	_indexar_predios_por_chunk()
	_indexar_predios_2p5d_por_chunk()
	_indexar_arvores_por_chunk()
	_indexar_ruas_nomeadas()
	print("[WorldOSM] %d prédios OSM, %d 2.5D e %d árvores indexados em chunks." % [
		_dados["predios"].size(),
		(_dados_2p5d["predios"].size() if _dados_2p5d else 0),
		(_dados_features.get("arvores", []).size() if _dados_features else 0)
	])
	# Garante que o próximo atualizar_parallax recarregue os chunks com os dados já indexados
	_chunk_player = Vector2(-999.0, -999.0)
	if OS.get_name() == "HTML5":
		if _dados_meta != null:
			_iniciar_satelite(_dados_meta, URL_BASE + "/assets/tiles/")
	else:
		_carregar_satelite()


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


func _indexar_arvores_por_chunk() -> void:
	if _dados_features == null:
		return
	var arvores = _dados_features.get("arvores", [])
	for pt in arvores:
		var k = _chunk_key_pre(pt[0], pt[1])
		if not _arvores_chunk.has(k):
			_arvores_chunk[k] = []
		_arvores_chunk[k].append(Vector2(pt[0], pt[1]))


var _pos_pre_atual: Vector2 = Vector2.ZERO

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

	for pos_arvore in _arvores_chunk.get(k, []):
		_criar_arvore_em(corpo, pos_arvore, k)

	var visuais:   Array = []
	var dinamicos: Array = []
	for predio in _predios_2p5d_chunk.get(k, []):
		var entry = _criar_predio_2p5d_lazy(corpo, predio, visuais)
		if entry:
			dinamicos.append(entry)
			_predios_dinamicos.append(entry)
	_visuais_chunk[k]   = visuais
	_dinamicos_chunk[k] = dinamicos

	# Inicializa os quads de todos os prédios do chunk imediatamente,
	# sem filtro de distância, para que apareçam visíveis desde o primeiro frame.
	for entry in dinamicos:
		var dir    = (entry.centro - _pos_pre_atual).normalized()
		var offset = dir * (entry.wall_px as float)
		entry.roof.position      = offset
		entry["ultimo_offset"]   = offset
		var pool  = entry.pool
		var quads = entry.quads
		var n     = pool.size()
		for i in range(n):
			var a = pool[i]
			var b = pool[(i + 1) % n]
			quads[i].polygon = PoolVector2Array([a, b, b + offset, a + offset])


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


func _criar_arvore_em(corpo: StaticBody2D, pos_arvore: Vector2, k: String) -> void:
	var pos_jogo = pos_arvore * ESCALA
	
	# 1. Colisão do tronco (círculo pequeno de raio ~6px no jogo)
	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 6.0
	col.shape = circle
	col.position = pos_jogo
	corpo.add_child(col)
	
	# Determinístico baseado na posição (escala varia de 0.85 a 1.2)
	var seed_val = int(abs(pos_arvore.x * 123.45 + pos_arvore.y * 678.90)) % 1000
	var escala_arvore = 0.85 + (seed_val / 1000.0) * 0.35
	
	# 2. Sombra da copa (abaixo de pedestres e carros)
	var shadow = Sprite.new()
	shadow.texture = _obter_textura_sombra_procedural()
	shadow.scale = Vector2(escala_arvore, escala_arvore)
	shadow.position = pos_jogo + Vector2(5.0, 7.0)
	shadow.z_index = -5
	corpo.add_child(shadow)
	
	# 3. Copa da árvore (acima dos carros e prédios de z_index baixo)
	var canopy = Sprite.new()
	canopy.texture = _obter_textura_arvore_procedural()
	canopy.scale = Vector2(escala_arvore, escala_arvore)
	canopy.position = pos_jogo + Vector2(0.0, -6.0)
	canopy.z_index = 6
	corpo.add_child(canopy)


func _obter_textura_arvore_procedural() -> Texture:
	if _tex_arvore_procedural == null:
		_tex_arvore_procedural = MapFeatures.obter_textura_arvore_procedural()
	return _tex_arvore_procedural


func _obter_textura_sombra_procedural() -> Texture:
	if _tex_sombra_procedural == null:
		_tex_sombra_procedural = MapFeatures.obter_textura_sombra_procedural()
	return _tex_sombra_procedural


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
		"pool":          pool,
		"wall_px":       wall_px,
		"centro":        _centroide(pool),
		"roof":          visual,
		"quads":         quads,
		"ultimo_offset": Vector2.INF,
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
		_dados_meta = parse_json(body.get_string_from_utf8())
		if _dados_meta:
			print("[WorldOSM] meta.json OK")
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

func _iniciar_satelite(meta: Dictionary, caminho_base: String) -> void:
	var stream = load("res://scripts/satelite_stream.gd").new()
	stream.inicializar(null, meta, caminho_base)
	add_child(stream)
	set_meta("satelite_stream", stream)
	print("[WorldOSM] Satélite pronto (zoom %d, base: %s)." % [meta["zoom"], caminho_base])

func _carregar_satelite():
	var arq = File.new()
	if not arq.file_exists(CAMINHO_META):
		print("[WorldOSM] meta.json não encontrado. Rode: python3 baixar_tiles.py")
		_fundo_fallback()
		return
	arq.open(CAMINHO_META, File.READ)
	var meta = parse_json(arq.get_as_text())
	arq.close()
	if meta:
		_iniciar_satelite(meta, "res://assets/tiles/")

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
	bg.color = Color(0.14, 0.16, 0.18)
	bg.z_index = -50
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
		var extra = 3.5
		var calcada = Line2D.new()
		var pts = PoolVector2Array()
		for p in rua["pontos"]: pts.append(Vector2(p[0], p[1]))
		calcada.points = pts
		calcada.texture = _obter_textura_pedra_portuguesa()
		calcada.texture_mode = Line2D.LINE_TEXTURE_TILE
		calcada.default_color = Color(1.0, 1.0, 1.0, 0.90) # Preserva o brilho e opacidade da textura
		calcada.width = _largura_calcada(largura, extra)
		calcada.joint_mode = Line2D.LINE_JOINT_ROUND
		calcada.begin_cap_mode = Line2D.LINE_CAP_ROUND
		calcada.end_cap_mode = Line2D.LINE_CAP_ROUND
		calcada.round_precision = _round_prec
		calcada.z_index = _z_rua(largura) - 30
		add_child(calcada)

	# Ruas
	for rua in ruas_ordenadas:
		var largura    = float(rua["largura"])
		var tipo_rua   = rua.get("tipo", "")
		# Ciclovia: campo tipo == "cycleway", ou JSON antigo sem tipo onde largura == 3
		var eh_ciclovia = (tipo_rua == "cycleway") or (tipo_rua == "" and largura == 3)
		var linha = Line2D.new()
		var pts = PoolVector2Array()
		for p in rua["pontos"]: pts.append(Vector2(p[0], p[1]))
		linha.points = pts
		
		# Determina a largura real da rua (asfalto)
		var largura_asfalto = _mult_rua(largura) * largura
		
		if largura <= 3:
			linha.texture = _obter_textura_viela_procedural()
			linha.texture_mode = Line2D.LINE_TEXTURE_TILE
			if eh_ciclovia:
				linha.default_color = Color(0.68, 0.26, 0.18, 1.00) # vermelho terracota para ciclovia
			else:
				linha.default_color = Color(1.00, 1.00, 1.00, 1.00) # branco para vielas/footways/paths
		else:
			linha.texture = _obter_textura_asfalto_procedural()
			linha.texture_mode = Line2D.LINE_TEXTURE_TILE
			linha.default_color = _cor_rua(largura)
			
		linha.width = largura_asfalto
		linha.joint_mode = Line2D.LINE_JOINT_ROUND
		linha.begin_cap_mode = Line2D.LINE_CAP_ROUND
		linha.end_cap_mode = Line2D.LINE_CAP_ROUND
		linha.round_precision = _round_prec
		linha.z_index = _z_rua(largura) - 24
		
		# Só adiciona meio-fio (curb) e sombra 2.5D para ruas com asfalto (largura > 3)
		if largura > 3:
			# 1. Sombra projetada do meio-fio na calçada (Efeito de elevação 2.5D)
			var sombra_meio_fio = Line2D.new()
			var pts_sombra = PoolVector2Array()
			# Desloca a sombra ligeiramente para o sudeste (simula luz solar vindo do noroeste)
			for pt in pts:
				pts_sombra.append(pt + Vector2(1.8, 2.8))
			sombra_meio_fio.points = pts_sombra
			sombra_meio_fio.default_color = Color(0.0, 0.0, 0.0, 0.35) # sombra suave
			sombra_meio_fio.width = largura_asfalto + 5.0
			sombra_meio_fio.joint_mode = Line2D.LINE_JOINT_ROUND
			sombra_meio_fio.begin_cap_mode = Line2D.LINE_CAP_ROUND
			sombra_meio_fio.end_cap_mode = Line2D.LINE_CAP_ROUND
			sombra_meio_fio.round_precision = _round_prec
			sombra_meio_fio.z_index = linha.z_index - 2
			add_child(sombra_meio_fio)

			# 2. Borda física do meio-fio (concreto cinza escuro elevado)
			var borda_meio_fio = Line2D.new()
			borda_meio_fio.points = pts
			borda_meio_fio.default_color = Color(0.24, 0.24, 0.24, 1.00) # concreto cinza do meio-fio
			borda_meio_fio.width = largura_asfalto + 2.5
			borda_meio_fio.joint_mode = Line2D.LINE_JOINT_ROUND
			borda_meio_fio.begin_cap_mode = Line2D.LINE_CAP_ROUND
			borda_meio_fio.end_cap_mode = Line2D.LINE_CAP_ROUND
			borda_meio_fio.round_precision = _round_prec
			borda_meio_fio.z_index = linha.z_index - 1
			add_child(borda_meio_fio)

		add_child(linha)

		# Faixa central pontilhada: avenidas e ciclovias
		if largura >= 7 or eh_ciclovia:
			var faixa = Line2D.new()
			faixa.points = pts
			faixa.default_color = Color(1.0, 1.0, 1.0, 0.85)
			faixa.width = 0.10 if eh_ciclovia else 0.15
			faixa.texture = _obter_textura_pontilhada()
			faixa.texture_mode = Line2D.LINE_TEXTURE_TILE
			faixa.joint_mode = Line2D.LINE_JOINT_ROUND
			faixa.begin_cap_mode = Line2D.LINE_CAP_ROUND
			faixa.end_cap_mode = Line2D.LINE_CAP_ROUND
			faixa.round_precision = _round_prec
			faixa.z_index = linha.z_index + 1
			add_child(faixa)

func _largura_calcada(largura: float, extra: float) -> float:
	if largura >= 11: return largura * 1.40 + extra * 2
	if largura >= 7 and largura <= 10: return largura * 1.55 + extra * 2
	if largura == 6: return largura * 1.00 + extra * 2
	return largura + extra * 2

func _cor_rua(largura: float) -> Color:
	if largura >= 11: return Color(0.93, 0.85, 0.48, 1.00)
	if largura >= 7 and largura <= 10: return Color(0.22, 0.24, 0.26, 1.00)
	if largura == 6: return Color(0.22, 0.24, 0.26, 1.00)
	if largura >= 4 and largura <= 5: return Color(0.22, 0.24, 0.26, 1.00)
	if largura == 3: return Color(0.68, 0.26, 0.18, 1.00)
	if largura <= 2: return Color(1.00, 1.00, 1.00, 1.00)
	return Color(0.3, 0.3, 0.3, 1.00)

func _mult_rua(largura: float) -> float:
	if largura >= 11: return 1.40
	if largura >= 7 and largura <= 10: return 1.55
	if largura == 6: return 1.00
	if largura >= 4 and largura <= 5: return 1.90
	if largura == 3: return 1.50
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
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	return tex


func _criar_features(dados: Dictionary) -> void:
	MapFeatures.criar_features(self, dados)



func _indexar_ruas_nomeadas() -> void:
	for rua in _dados["ruas"]:
		var nome: String = rua.get("nome", "")
		if nome == "":
			continue
		var pts = PoolVector2Array()
		var cx_sum = 0.0
		var cy_sum = 0.0
		for p in rua["pontos"]:
			pts.append(Vector2(p[0], p[1]))
			cx_sum += p[0]
			cy_sum += p[1]
		var entry = {"nome": nome, "pts": pts}
		_ruas_nomeadas.append(entry)
		var ck = _chunk_key_pre(cx_sum / pts.size(), cy_sum / pts.size())
		if not _ruas_nomeadas_chunk.has(ck):
			_ruas_nomeadas_chunk[ck] = []
		_ruas_nomeadas_chunk[ck].append(entry)


func rua_proxima(pos_jogo: Vector2) -> String:
	if _ruas_nomeadas_chunk.empty():
		return ""
	var pos_pre   = pos_jogo / ESCALA
	var melhor    = ""
	var melhor_d2 = 350.0 * 350.0
	var cx = int(pos_pre.x / CHUNK_SIZE_PRE)
	var cy = int(pos_pre.y / CHUNK_SIZE_PRE)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k = str(cx + dx) + "_" + str(cy + dy)
			for r in _ruas_nomeadas_chunk.get(k, []):
				for pt in r["pts"]:
					var d2 = pt.distance_squared_to(pos_pre)
					if d2 < melhor_d2:
						melhor_d2 = d2
						melhor    = r["nome"]
	return melhor


func _centroide(pool: PoolVector2Array) -> Vector2:
	var c = Vector2.ZERO
	for v in pool:
		c += v
	return c / pool.size()


# Chamado por main.gd a cada frame — atualiza chunks e parallax dos prédios 2.5D
func atualizar_parallax(pos_jogo: Vector2) -> void:
	# Lazy loading: verifica se o player mudou de chunk
	var pos_pre    = pos_jogo / ESCALA
	_pos_pre_atual = pos_pre
	var chunk_novo = Vector2(int(pos_pre.x / CHUNK_SIZE_PRE), int(pos_pre.y / CHUNK_SIZE_PRE))
	if chunk_novo != _chunk_player:
		_chunk_player = chunk_novo
		_atualizar_chunks()

	if _predios_dinamicos.empty():
		return

	# Mobile: atualiza parallax a cada 2 frames para poupar CPU/GPU
	_parallax_frame = (_parallax_frame + 1) % 2
	if _is_mobile and _parallax_frame != 0:
		return

	var raio2 = (150.0 * 150.0) if _is_mobile else (250.0 * 250.0)

	for dados in _predios_dinamicos:
		var centro: Vector2 = dados.centro
		if centro.distance_squared_to(pos_pre) > raio2:
			continue

		var dir    = (centro - pos_pre).normalized()
		var offset = dir * (dados.wall_px as float)

		if dados["ultimo_offset"].distance_squared_to(offset) < 0.25:
			continue
		dados["ultimo_offset"] = offset

		# Telhado: desloca o nó sem reconstruir o polygon
		dados.roof.position = offset

		# Quads base→telhado
		var pool:  PoolVector2Array = dados.pool
		var quads: Array            = dados.quads
		var n                       = pool.size()
		for i in range(n):
			var a = pool[i]
			var b = pool[(i + 1) % n]
			quads[i].polygon = PoolVector2Array([a, b, b + offset, a + offset])


func _obter_textura_pontilhada() -> Texture:
	if _tex_pontilhado:
		return _tex_pontilhado
	
	var img = Image.new()
	# Cria uma imagem de 64x2 pixels para afastar mais as listras (gaps maiores)
	img.create(64, 2, false, Image.FORMAT_RGBA8)
	img.lock()
	for x in range(64):
		for y in range(2):
			if x < 16:
				img.set_pixel(x, y, Color(1, 1, 1, 0.85)) # Tracinho branco (16px)
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0.0))  # Espaço vazio/afastamento (48px)
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	_tex_pontilhado = tex
	return _tex_pontilhado





func _obter_textura_pedra_portuguesa() -> Texture:
	var img = Image.new()
	img.create(32, 32, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765 # Semente fixa para padrão consistente
	
	# Gera um mosaico simulando as pedras pretas e brancas assentadas artesanalmente
	for x in range(32):
		for y in range(32):
			# Cria um padrão ondulante suave baseado nas coordenadas para simular os desenhos de Santos
			var onda = sin(x * 0.4) + cos(y * 0.4)
			var r = rng.randf()
			
			var cor: Color
			if abs(onda) < 0.45:
				# Pedras Pretas (com leve variação de cinza para textura mineral)
				var v = 0.16 + r * 0.08
				cor = Color(v, v, v, 1.0)
			else:
				# Pedras Brancas/Claras (com leve variação de cinza claro/creme)
				var v = 0.82 + r * 0.10
				cor = Color(v, v, v - 0.04, 1.0) # levemente creme
				
			img.set_pixel(x, y, cor)
			
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT)
	return tex


func _obter_textura_viela_procedural() -> Texture:
	var img = Image.new()
	img.create(16, 16, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321 # semente fixa para consistência
	
	# Gera um padrão liso de cinza muito claro (quase branco) pixel art sem divisórias
	for x in range(16):
		for y in range(16):
			var r = rng.randf()
			# Tom base de cinza bem claro (quase branco): [0.85, 0.95]
			var base_v = 0.85 + r * 0.10
			var c = Color(base_v, base_v, base_v, 1.0)
			img.set_pixel(x, y, c)
			
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT) # Sem filtragem para manter pixel art nítido
	return tex


func _obter_textura_asfalto_procedural() -> Texture:
	var img = Image.new()
	img.create(16, 16, false, Image.FORMAT_RGBA8)
	img.lock()
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765 # semente fixa para consistência
	
	# Gera um padrão granulado/áspero de asfalto pixel art
	for x in range(16):
		for y in range(16):
			var r = rng.randf()
			# Tom base de asfalto cinza médio/escuro neut: [0.80, 1.00]
			var base_v = 0.80 + r * 0.20
			var c = Color(base_v, base_v, base_v, 1.0)
			img.set_pixel(x, y, c)
			
	img.unlock()
	
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_REPEAT) # Sem filtragem para manter pixel art nítido
	return tex
